defmodule ComcentWeb.Internal.HttpapiController do
  use ComcentWeb, :controller
  require Logger
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.RedisClient
  alias Comcent.DialUtils
  alias Comcent.QueueManager
  alias ExPhoneNumber
  alias Comcent.Repo.Queue

  def create(conn, params) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, process_httapi_request(params))
  end

  # Generate XML from the provided parameters
  defp generate_xml_from_params(params) do
    """
    <currentNodeId>#{params["nodeId"]}</currentNodeId>
    <fromUser>#{params["fromUser"]}</fromUser>
    <fromDomain>#{params["fromDomain"]}</fromDomain>
    <toUser>#{params["toUser"]}</toUser>
    <toDomain>#{params["toDomain"]}</toDomain>
    <pathCount>#{params["pathCount"]}</pathCount>
    <comcentContextId>#{params["comcentContextId"]}</comcentContextId>
    <callId>#{params["callId"]}</callId>
    <freeSwitchIpAddress>#{params["freeSwitchIpAddress"]}</freeSwitchIpAddress>
    """
  end

  # Process the HTTP API request based on the parameters
  defp process_httapi_request(params) do
    previous_node_id = params["currentNodeId"]

    cond do
      params["exiting"] ->
        Logger.info("Exiting")
        break_response()

      previous_node_id == "hangup" ->
        Logger.info("Previous Node is hangup node")
        break_response()

      true ->
        # Extract parameters
        httapi_params = extract_params_from_body(params)

        # Find the SIP number
        sip_number = find_sip_number(httapi_params["toUser"])

        IO.puts("SIP Number: #{inspect(sip_number)}")

        if is_nil(sip_number) || is_nil(sip_number.inbound_flow_graph) do
          Logger.info("No number found or graph not found")
          hangup_response()
        else
          # Set toName if not present
          httapi_params = Map.put_new(httapi_params, "toName", sip_number.name)

          # Process the inbound flow graph
          inbound_flow_graph = decode_inbound_flow_graph(sip_number.inbound_flow_graph)
          nodes = inbound_flow_graph["nodes"]
          previous_node = nodes[previous_node_id]

          if previous_node do
            case previous_node["type"] do
              "Dial" ->
                Logger.info("Previous Node is Dial node")
                after_dial_response(params, sip_number)

              "DialGroup" ->
                Logger.info("Previous Node is Dial group node")
                after_dial_response(params, sip_number)

              "Menu" ->
                Logger.info("Previous Node is Menu node")
                after_menu_response(params, sip_number)

              _ ->
                Logger.info("No match for the previous node's type #{previous_node["type"]}")
                hangup_response()
            end
          else
            Logger.info("Previous Node is null starting from start node")
            start_node_id = inbound_flow_graph["start"]
            httapi_params = Map.put(httapi_params, "pathCount", 20)
            traverse_graph(inbound_flow_graph, start_node_id, httapi_params, sip_number)
          end
        end
    end
  end

  # Extract parameters from the request body
  defp extract_params_from_body(body) do
    path_count =
      if body["pathCount"] do
        Integer.parse("#{body["pathCount"]}") |> elem(0)
      else
        20
      end

    %{
      "nodeId" => body["currentNodeId"],
      "fromUser" => body["variable_sip_from_user"] || body["fromUser"],
      "fromDomain" => body["variable_sip_from_host"] || body["fromDomain"],
      "toUser" => body["variable_sip_to_user"] || body["toUser"],
      "toDomain" => body["variable_sip_to_host"] || body["toDomain"],
      "toName" => body["toName"] || "",
      "pathCount" => path_count,
      "comcentContextId" => body["variable_comcent_context_id"],
      "callId" => body["variable_uuid"],
      "freeSwitchIpAddress" => body["variable_local_media_ip"]
    }
  end

  # Traverse the flow graph
  defp traverse_graph(inbound_flow_graph, node_id, params, sip_number) do
    node = inbound_flow_graph["nodes"][node_id]

    if is_nil(node) || params["pathCount"] <= 0 do
      hangup_response()
    else
      case node["type"] do
        "Dial" ->
          Logger.info("Dial node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))
          dial_response(params, node, sip_number)

        "DialGroup" ->
          Logger.info("Dial Group node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))
          dial_group_response(params, node, sip_number)

        "Play" ->
          Logger.info("Play node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))
          play_response(params, node["data"]["media"])

        "WeekTime" ->
          Logger.info("WeekTime node")
          params = Map.update!(params, "pathCount", &(&1 - 1))
          next_node_id = handle_week_time_node(node)
          traverse_graph(inbound_flow_graph, next_node_id, params, sip_number)

        "Queue" ->
          Logger.info("Queue node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))

          queue_response(
            params,
            sip_number.org.subdomain,
            node["data"]["queue"]
          )

        "Menu" ->
          Logger.info("Menu node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))
          menu_response(params, sip_number)

        "VoiceBot" ->
          Logger.info("VoiceBot node")
          params = Map.put(params, "nodeId", node["id"])
          params = Map.update!(params, "pathCount", &(&1 - 1))
          voice_bot_response(params, node, sip_number)

        _ ->
          hangup_response()
      end
    end
  end

  # Handle week time node
  defp handle_week_time_node(node) do
    timezone = node["data"]["timezone"] || "UTC"
    now = DateTime.utc_now() |> DateTime.shift_zone!(timezone)
    day_of_week = now |> Date.day_of_week() |> to_day_of_week_string()
    day_config = node["data"][day_of_week]

    if not day_config["include"] do
      Logger.info("Day not included in week time node #{day_of_week}")
      node["outlets"]["false"]
    else
      if Enum.any?(day_config["timeSlots"], fn time_slot ->
           {from, to} = parse_time_slot(time_slot, timezone)
           now |> DateTime.after?(from) and now |> DateTime.before?(to)
         end) do
        Logger.info("Now included in week time node #{day_of_week}")
        node["outlets"]["true"]
      else
        Logger.info("Now not included in week time node #{day_of_week}")
        node["outlets"]["false"]
      end
    end
  end

  defp to_day_of_week_string(day_of_week) do
    case day_of_week do
      1 -> "mon"
      2 -> "tue"
      3 -> "wed"
      4 -> "thu"
      5 -> "fri"
      6 -> "sat"
      7 -> "sun"
      # Default to Monday if invalid
      _ -> "mon"
    end
  end

  defp parse_time_slot(time_slot, timezone) do
    from = Map.get(time_slot, "from", "00:00")
    to = Map.get(time_slot, "to", "23:59")

    [from_hour, from_minute] =
      if is_binary(from) && String.contains?(from, ":") do
        String.split(from, ":") |> Enum.map(&String.to_integer/1)
      else
        [0, 0]
      end

    [to_hour, to_minute] =
      if is_binary(to) && String.contains?(to, ":") do
        String.split(to, ":") |> Enum.map(&String.to_integer/1)
      else
        [23, 59]
      end

    now = DateTime.utc_now() |> DateTime.shift_zone!(timezone)

    from =
      now
      |> DateTime.add(-now.hour + from_hour, :hour)
      |> DateTime.add(-now.minute + from_minute, :minute)
      |> DateTime.add(-now.second, :second)

    to =
      now
      |> DateTime.add(-now.hour + to_hour, :hour)
      |> DateTime.add(-now.minute + to_minute, :minute)
      |> DateTime.add(-now.second, :second)

    {from, to}
  end

  # Response templates for different scenarios
  defp break_response do
    """
    <document type="xml/freeswitch-httapi">
      <work>
        <break />
      </work>
    </document>
    """
  end

  defp hangup_response do
    # Use the dialplan `hangup` application via <execute>, NOT the bare
    # <hangup> action. mod_httapi's <hangup> moves the channel straight
    # from CS_EXECUTE to CS_DESTROY, skipping the CS_HANGUP state where
    # sofia normally emits the SIP BYE. The PSTN side then sat with the
    # call open until the caller gave up on their own (verified on a
    # fresh DO droplet — twilio sent its own BYE 60+s after the agent
    # hung up). Routing through the dialplan engine takes the standard
    # state path so sofia sends BYE immediately.
    """
    <document type="xml/freeswitch-httapi">
      <params>
        <currentNodeId>hangup</currentNodeId>
      </params>
      <work>
        <execute application="hangup" data="NORMAL_CLEARING" />
      </work>
    </document>
    """
  end

  # Placeholder implementations for other responses - these would need to be implemented
  # with actual business logic based on your application requirements

  defp after_dial_response(body, sip_number) do
    timeout_node_id =
      if is_nil(body["variable_transfer_history"]) and
           body["last_bridge_hangup_cause"] == "NO_ANSWER" do
        previous_node_id = body["currentNodeId"]
        inbound_flow_graph = decode_inbound_flow_graph(sip_number.inbound_flow_graph)
        previous_node = inbound_flow_graph["nodes"][previous_node_id]
        previous_node["outlets"]["timeout"]
      end

    if timeout_node_id do
      inbound_flow_graph = decode_inbound_flow_graph(sip_number.inbound_flow_graph)
      params = extract_params_from_body(body)
      traverse_graph(inbound_flow_graph, timeout_node_id, params, sip_number)
    else
      hangup_response()
    end
  end

  defp after_menu_response(body, sip_number) do
    Logger.info("Previous Node is Menu node")
    params = extract_params_from_body(body)
    inbound_flow_graph = decode_inbound_flow_graph(sip_number.inbound_flow_graph)
    selected_menu = body["selectedMenu"]
    previous_node_id = body["currentNodeId"]
    previous_node = inbound_flow_graph["nodes"][previous_node_id]
    outlet = previous_node["outlets"][selected_menu]

    if outlet do
      traverse_graph(inbound_flow_graph, outlet, params, sip_number)
    else
      hangup_response()
    end
  end

  defp dial_response(params, node, sip_number) do
    # Determine the dial string based on whether the target is a phone number or internal extension
    dial_target = get_in(node, ["data", "to"])

    dial_string =
      if is_valid_phone_number(dial_target) do
        # External phone number - create a dial string for SIP trunk
        spoof_number =
          if get_in(node, ["data", "shouldSpoof"]) do
            params["fromUser"]
          else
            nil
          end

        DialUtils.create_dial_string_for_sip_trunk(
          sip_number.number,
          dial_target,
          sip_number.sip_trunk.outbound_contact,
          spoof_number
        )
      else
        # Internal extension - create a dial string for user
        DialUtils.create_dial_string_for_user(dial_target, sip_number.org.subdomain)
      end

    # Get timeout from node data or use default
    timeout = get_in(node, ["data", "timeout"]) || 20

    """
    <document type="xml/freeswitch-httapi">
      <params>
        #{generate_xml_from_params(params)}
      </params>
      <variables>
        <call_timeout>#{timeout}</call_timeout>
      </variables>
      <work>
        <execute application="set" data="sip_h_X-Inbound-Info=:#{params["toUser"]}:#{params["toName"] || ""}" />
        <execute application="bridge" data="#{dial_string}" />
        <getVariable name="last_bridge_hangup_cause" />
      </work>
    </document>
    """
  end

  # Helper function to check if a string is a valid phone number using ex_phone_number
  defp is_valid_phone_number(number) do
    case ExPhoneNumber.parse(number, nil) do
      {:ok, phone_number} -> ExPhoneNumber.is_valid_number?(phone_number)
      _ -> false
    end
  end

  defp dial_group_response(params, node, sip_number) do
    # Map each phone number in the "to" array to its appropriate dial string
    dial_strings =
      get_in(node, ["data", "to"])
      |> Enum.map(fn phone_number ->
        if is_valid_phone_number(phone_number) do
          # External phone number - create a dial string for SIP trunk
          spoof_number =
            if get_in(node, ["data", "shouldSpoof"]) do
              params["fromUser"]
            else
              nil
            end

          DialUtils.create_dial_string_for_sip_trunk(
            sip_number.number,
            phone_number,
            sip_number.sip_trunk.outbound_contact,
            spoof_number
          )
        else
          # Internal extension - create a dial string for user
          DialUtils.create_dial_string_for_user(phone_number, sip_number.org.subdomain)
        end
      end)
      |> Enum.join(":_:")

    # Get timeout from node data or use default
    timeout = get_in(node, ["data", "timeout"]) || 20

    """
    <document type="xml/freeswitch-httapi">
      <params>
        #{generate_xml_from_params(params)}
      </params>
      <variables>
        <call_timeout>#{timeout}</call_timeout>
      </variables>
      <work>
        <execute application="set" data="sip_h_X-Inbound-Info=:#{params["toUser"]}:#{params["toName"] || ""}" />
        <execute application="bridge" data="#{dial_strings}" />
        <getVariable name="last_bridge_hangup_cause" />
      </work>
    </document>
    """
  end

  defp play_response(params, media) do
    """
    <document type="xml/freeswitch-httapi">
      <params>
        #{generate_xml_from_params(params)}
      </params>
      <work>
        <playback file="#{convert_media_to_http(media)}" name="playback" />
      </work>
    </document>
    """
  end

  defp queue_response(params, subdomain, queue_name) do
    # Add call to queue using QueueManager
    queue = Queue.get_queue_by_name_and_subdomain(queue_name, subdomain)

    case QueueManager.add_call_to_queue(%Comcent.QueueManager.QueuedCallDetails{
           subdomain: subdomain,
           queue_id: queue.id,
           queue_name: queue_name,
           call_id: params["callId"],
           freeswitch_ip_address: params["freeSwitchIpAddress"],
           date_time: DateTime.utc_now(),
           to_user: params["toUser"],
           to_name: params["toName"],
           from_user: params["fromUser"],
           from_name: params["fromName"],
           comcent_context_id: params["comcentContextId"]
         }) do
      :ok ->
        Logger.info(
          "Successfully added call #{params["callId"]} to queue #{queue_name}@#{subdomain}"
        )

        """
        <document type="xml/freeswitch-httapi">
          <params>
            #{generate_xml_from_params(params)}
          </params>
          <variables>
            <cc_export_vars>comcent_context_id,comcent_subdomain,comcent_recording_bucket_name,comcent_waiting_queue_id</cc_export_vars>
            <comcent_waiting_queue_id>#{queue.id}</comcent_waiting_queue_id>
          </variables>
          <work>
            <playback file="local_stream://moh" name="moh-playback" />
          </work>
        </document>
        """

      {:error, reason} ->
        Logger.error(
          "Failed to add call #{params["callId"]} to queue #{queue_name}@#{subdomain}: #{inspect(reason)}"
        )

        # TODO: Play recording before hanging up
        hangup_response()
    end
  end

  defp menu_response(params, sip_number) do
    # Parse the inbound flow graph to get the node data
    inbound_flow_graph = decode_inbound_flow_graph(sip_number.inbound_flow_graph)
    node = inbound_flow_graph["nodes"][params["nodeId"]]

    # Extract the outlet keys to create bindings
    outlet_keys = node["outlets"] || %{}

    bindings =
      outlet_keys
      |> Map.keys()
      |> Enum.map(fn key -> "<bind>#{key}</bind>" end)
      |> Enum.join("\n      ")

    # Set default values for menu properties if not specified
    prompt_audio = get_in(node, ["data", "promptAudio"]) || ""
    error_audio = get_in(node, ["data", "errorAudio"]) || ""
    multi_digit_wait_time = get_in(node, ["data", "multiDigitWaitTime"]) || "2000"
    after_prompt_wait_time = get_in(node, ["data", "afterPromptWaitTime"]) || "5000"
    repeat = get_in(node, ["data", "repeat"]) || "1"

    """
    <document type="xml/freeswitch-httapi">
      <params>
        #{generate_xml_from_params(params)}
      </params>
      <work>
        <playback
          file="#{convert_media_to_http(prompt_audio)}"
          error-file="#{convert_media_to_http(error_audio)}"
          digit-timeout="#{multi_digit_wait_time}"
          input-timeout="#{after_prompt_wait_time}"
          loops="#{repeat}" name="selectedMenu">
          #{bindings}
        </playback>
        <getVariable name="selectedMenu" />
      </work>
    </document>
    """
  end

  defp decode_inbound_flow_graph(inbound_flow_graph) when is_binary(inbound_flow_graph) do
    Jason.decode!(inbound_flow_graph)
  end

  defp decode_inbound_flow_graph(inbound_flow_graph) when is_map(inbound_flow_graph) do
    inbound_flow_graph
  end

  defp voice_bot_response(params, node, sip_number) do
    # Get voice bot ID from the node data
    voice_bot_id = get_in(node, ["data", "voice_bot_id"])

    if is_nil(voice_bot_id) do
      Logger.error("No voice bot ID specified in node data")
      hangup_response()
    else
      # Find the voice bot in the database
      voice_bot = find_voice_bot(voice_bot_id, sip_number.org.subdomain)

      if is_nil(voice_bot) do
        Logger.error(
          "Voice bot with ID #{voice_bot_id} not found for org #{sip_number.org.subdomain}"
        )

        hangup_response()
      else
        # Get a voice bot IP address
        case get_voice_bot_ip_address() do
          nil ->
            Logger.error("No voice bot available")
            hangup_response()

          voice_bot_ip ->
            # Create a dial string for the voice bot
            dial_string = create_dial_string_for_voice_bot(voice_bot_id, voice_bot_ip)
            timeout = 20

            """
            <document type="xml/freeswitch-httapi">
            <params>
              #{generate_xml_from_params(params)}
            </params>
            <variables>
              <call_timeout>#{timeout}</call_timeout>
            </variables>
            <work>
              <execute application="set" data="sip_h_X-Comcent-Context-Id=#{params["comcentContextId"]}" />
              <execute application="bridge" data="#{dial_string}" />
              </work>
            </document>
            """
        end
      end
    end
  end

  # Helper function to convert media paths to HTTP URLs
  defp convert_media_to_http(media_path) when is_binary(media_path) do
    base_url = System.get_env("INTERNAL_API_BASE_URL")

    if String.starts_with?(media_path, "s3://") do
      # Split the path components
      path_parts = String.split(media_path, "/")

      # Get the subdomain (3rd from last) and filename (last part)
      parts_length = length(path_parts)
      subdomain = Enum.at(path_parts, parts_length - 3)
      file_name = List.last(path_parts)

      # Construct the HTTP URL
      "#{base_url}/playback/#{subdomain}/#{file_name}"
    else
      # Return the original path for non-s3 media
      media_path
    end
  end

  defp convert_media_to_http(nil), do: ""

  # Helper function to find a voice bot in the database
  defp find_voice_bot(voice_bot_id, subdomain) do
    query =
      from(vb in "voice_bots",
        join: o in Comcent.Schemas.Org,
        on: vb.org_id == o.id,
        where: vb.id == ^voice_bot_id and o.subdomain == ^subdomain,
        select: %{
          id: vb.id,
          name: vb.name,
          instructions: vb.instructions,
          not_to_do_instructions: vb.not_to_do_instructions,
          greeting_instructions: vb.greeting_instructions,
          mcp_servers: vb.mcp_servers,
          api_key: vb.api_key,
          is_hangup: vb.is_hangup,
          is_enqueue: vb.is_enqueue,
          queues: vb.queues,
          pipeline: vb.pipeline
        }
      )

    Repo.one(query)
  end

  # Helper function to get a voice bot IP address from Redis
  defp get_voice_bot_ip_address do
    # Get all voice bot IP keys from Redis
    with {:ok, keys} <- RedisClient.keys("voice.bot.ip.*") do
      # If no keys found, return nil
      if Enum.empty?(keys) do
        Logger.warning("No voice bot IP addresses found in Redis")
        nil
      else
        # Sort the keys
        sorted_keys = Enum.sort(keys)

        # Get the last used key from Redis
        with {:ok, last_used_key} <- RedisClient.get("voice.bot.last.used") do
          if is_nil(last_used_key) do
            # If no last used key, use the first key and update last used
            voice_bot_ip = extract_ip_from_redis_key(List.first(sorted_keys))
            RedisClient.set("voice.bot.last.used", List.first(sorted_keys))
            voice_bot_ip
          else
            # Find the index of the last used key
            last_used_index = Enum.find_index(sorted_keys, fn key -> key == last_used_key end)

            # If not found, start from the beginning
            last_used_index = if is_nil(last_used_index), do: -1, else: last_used_index

            # Get the next key (round-robin)
            next_index = rem(last_used_index + 1, length(sorted_keys))
            next_key = Enum.at(sorted_keys, next_index)

            # Extract the IP from the key
            voice_bot_ip = extract_ip_from_redis_key(next_key)

            # Update the last used key
            RedisClient.set("voice.bot.last.used", next_key)

            voice_bot_ip
          end
        else
          {:error, reason} ->
            Logger.error("Failed to get last used voice bot key: #{inspect(reason)}")
            # Fallback to using the first key
            voice_bot_ip = extract_ip_from_redis_key(List.first(sorted_keys))
            RedisClient.set("voice.bot.last.used", List.first(sorted_keys))
            voice_bot_ip
        end
      end
    else
      {:error, reason} ->
        Logger.error("Failed to get voice bot IP keys: #{inspect(reason)}")
        nil
    end
  end

  # Helper function to extract the IP address from a Redis key
  defp extract_ip_from_redis_key(key) when is_binary(key) do
    parts = String.split(key, ".")
    Enum.slice(parts, -4, 4) |> Enum.join(".")
  end

  defp extract_ip_from_redis_key(_), do: nil

  # Helper function to create a dial string for a voice bot
  defp create_dial_string_for_voice_bot(voice_bot_id, voice_bot_ip_address) do
    "[absolute_codec_string=PCMU,PCMA]sofia/internal/sip:#{voice_bot_id}@#{voice_bot_ip_address}:5080"
  end

  # Find SIP number in the database
  defp find_sip_number(number) do
    query =
      from(n in "numbers",
        join: o in "orgs",
        on: n.org_id == o.id,
        left_join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: n.number == ^number,
        select: %{
          number: n.number,
          name: n.name,
          inbound_flow_graph: n.inbound_flow_graph,
          org: %{
            id: o.id,
            subdomain: o.subdomain
          },
          sip_trunk: %{
            id: s.id,
            outbound_username: s.outbound_username,
            outbound_password: s.outbound_password,
            outbound_contact: s.outbound_contact
          }
        }
      )

    Repo.one(query)
  end
end
