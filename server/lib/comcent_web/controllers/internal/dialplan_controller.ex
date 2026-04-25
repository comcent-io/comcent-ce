defmodule ComcentWeb.Internal.DialplanController do
  use ComcentWeb, :controller
  require Logger
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.DialUtils
  alias Comcent.Repo.Queue

  def create(conn, params) do
    from_user = params["variable_sip_from_user"]
    from_domain = params["variable_sip_from_host"]
    destination_number = params["Hunt-Destination-Number"]
    to_domain = params["variable_sip_to_host"]
    outbound_number = params["variable_sip_h_X-outbound-number"]
    context = params["Caller-Context"]

    Logger.info(
      "fromUser: #{from_user}, fromDomain: #{from_domain}, toUser: #{destination_number}, toDomain: #{to_domain}, outboundNumber: #{outbound_number}, context: #{context}"
    )

    case process_dialplan_request(
           params,
           from_user,
           from_domain,
           destination_number,
           outbound_number,
           context
         ) do
      {:ok, response} ->
        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, response)

      {:not_found, message} ->
        conn
        |> put_status(404)
        |> text(message)

      {:not_authorized, message} ->
        conn
        |> put_status(403)
        |> text(message)
    end
  end

  defp process_dialplan_request(
         params,
         from_user,
         from_domain,
         destination_number,
         outbound_number,
         context
       ) do
    cond do
      # Internally Initiated call
      context == "default" ->
        Logger.info("Call initiated from internal agent.")
        referred_from = params["variable_sip_h_Referred-By"]
        Logger.info("referredFrom: #{referred_from}")

        {caller_subdomain, user} =
          extract_subdomain_and_user(referred_from, from_domain, from_user)

        caller_member = get_member(caller_subdomain, user)

        if !can_make_calls(caller_member) do
          Logger.info("Unable to make calls, wallet balance is low or the org is not active")
          {:not_authorized, not_allowed_response()}
        else
          transfer_ref = params["variable_sip_refer_to"]

          if transfer_ref do
            # Call transfer
            Logger.info("Call transfer found.")
            [_, user_with_domain] = String.split(transfer_ref, ":")
            [transfer_user, transfer_domain] = String.split(user_with_domain, "@")
            [subdomain | _] = String.split(transfer_domain, ".")

            # Make sure transfer within the same tenant
            if !String.contains?(params["variable_sip_h_Referred-By"], transfer_domain) do
              {:not_found, not_allowed_response()}
            else
              member = get_member(subdomain, transfer_user)

              if member do
                {:ok,
                 dial_member_dialplan(member, subdomain, "default", %{
                   address: "#{from_user}@#{caller_subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)}",
                   name: caller_member[:user][:name] || ""
                 })}
              else
                Logger.info("No member found for transfer")
                {:not_found, not_allowed_response()}
              end
            end
          else
            # Direct call
            Logger.info("Direct call found.")
            member = get_member(caller_subdomain, destination_number)

            if member do
              Logger.info("callerMember: #{inspect(caller_member)}")

              {:ok,
               dial_member_dialplan(member, caller_subdomain, "default", %{
                 address: "#{from_user}@#{caller_subdomain}.#{Application.fetch_env!(:comcent, :sip_domain)}",
                 name: caller_member[:user][:name] || ""
               })}
            else
              # External call
              Logger.info("External call found.")

              number =
                if outbound_number do
                  Logger.info(
                    "Finding number in org #{caller_subdomain} with phone number #{outbound_number}"
                  )

                  find_number_in_org(caller_subdomain, outbound_number)
                else
                  # default phone number
                  Logger.info("Finding default outbound number")
                  number = get_default_outbound_number_for_member(caller_subdomain, from_user)

                  if is_nil(number) do
                    Logger.info("No default outbound number found for member")
                    get_default_outbound_number_for_org(caller_subdomain)
                  else
                    number
                  end
                end

              if is_nil(number) do
                Logger.info("No number found")
                {:not_found, not_allowed_response()}
              else
                Logger.info("Dialing #{destination_number} via #{number.number}")
                {:ok, dial_trunk_dialplan(number, destination_number, caller_subdomain)}
              end
            end
          end
        end

      # Public context
      context == "public" ->
        is_redirect = params["Hunt-RDNIS"]

        if is_redirect do
          Logger.info("Redirect request found.")
          original_destination_number = params["variable_sip_to_user"]
          Logger.info("originalDestinationNumber: #{original_destination_number}")

          number = find_number_globally(original_destination_number)

          if is_nil(number) do
            {:not_found, not_allowed_response()}
          else
            member = get_member(number.org.subdomain, destination_number)

            if !can_make_calls_by_org_id(number.org.id) do
              Logger.info(
                "Unable to redirect calls, either the wallet balance is low or the subscription is not active"
              )

              {:not_authorized, not_allowed_response()}
            else
              if member do
                # internal redirect
                Logger.info("Internal redirect found.")

                {:ok,
                 dial_member_dialplan(member, number.org.subdomain, context, %{
                   address: "",
                   name: "",
                   via_number: number.number,
                   via_name: number.name
                 })}
              else
                Logger.info(
                  "No member found for redirect. Trying to see if queue is available with name #{destination_number}"
                )

                queue =
                  Queue.get_queue_by_name_and_subdomain(destination_number, number.org.subdomain)

                if queue do
                  Logger.info("Queue found.")

                  {:ok,
                   dial_queue_dialplan(%Comcent.QueueManager.QueuedCallDetails{
                     subdomain: number.org.subdomain,
                     queue_name: queue.name,
                     queue_id: queue.id,
                     call_id: params["variable_uuid"],
                     freeswitch_ip_address: params["variable_local_media_ip"],
                     date_time: DateTime.utc_now(),
                     to_user: destination_number,
                     to_name: number.name,
                     from_user: from_user,
                     from_name: "",
                     comcent_context_id: params["variable_comcent_context_id"]
                   })}
                else
                  # external redirect
                  Logger.info("External redirect found.")
                  {:ok, dial_trunk_dialplan(number, destination_number, number.org.subdomain)}
                end
              end
            end
          end
        else
          Logger.info("Inbound direct call found.")
          number = find_number_globally(destination_number)

          if is_nil(number) do
            {:not_found, not_allowed_response()}
          else
            if !can_make_calls_by_org_id(number.org.id) do
              Logger.info(
                "Unable to make inbound calls, either the wallet balance is low or the subscription is not active"
              )

              {:not_authorized, "Insufficient funds or organization inactive"}
            else
              Logger.info("Processing inbound call to #{destination_number}")
              {:ok, dial_httpapi_dialplan(destination_number, number.org.subdomain)}
            end
          end
        end

      # Default case for unknown context
      true ->
        {:not_found, not_allowed_response()}
    end
  end

  # Helper functions for dialplan processing

  defp extract_subdomain_and_user(referred_from, from_domain, from_user) do
    if referred_from do
      subdomain =
        referred_from |> String.split("@") |> Enum.at(1) |> String.split(".") |> Enum.at(0)

      user = referred_from |> String.split(":") |> Enum.at(1) |> String.split("@") |> Enum.at(0)
      {subdomain, user}
    else
      # acme.example.com
      [subdomain | _] = String.split(from_domain, ".")
      {subdomain, from_user}
    end
  end

  # Database access functions

  defp get_member(subdomain, username) do
    query =
      from(m in Comcent.Schemas.OrgMember,
        join: o in Comcent.Schemas.Org,
        on: m.org_id == o.id,
        join: u in Comcent.Schemas.User,
        on: m.user_id == u.id,
        where: m.username == ^username and o.subdomain == ^subdomain,
        select: %{
          username: m.username,
          sip_password: m.sip_password,
          org_id: m.org_id,
          extension_number: m.extension_number,
          user: %{
            id: u.id,
            name: u.name
          }
        }
      )

    Repo.one(query)
  end

  defp find_number_in_org(subdomain, number) do
    query =
      from(n in "numbers",
        join: o in "orgs",
        on: n.org_id == o.id,
        left_join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: n.number == ^number and o.subdomain == ^subdomain,
        select: %{
          id: n.id,
          number: n.number,
          name: n.name,
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

  defp find_number_globally(number) do
    query =
      from(n in "numbers",
        join: o in "orgs",
        on: n.org_id == o.id,
        left_join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: n.number == ^number,
        select: %{
          id: n.id,
          number: n.number,
          name: n.name,
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

  defp get_default_outbound_number_for_member(subdomain, username) do
    query =
      from(n in "numbers",
        join: o in "orgs",
        on: n.org_id == o.id,
        join: m in "org_members",
        on: n.id == m.default_number_id,
        left_join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: o.subdomain == ^subdomain and m.username == ^username,
        select: %{
          id: n.id,
          number: n.number,
          name: n.name,
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
        },
        limit: 1
      )

    Repo.one(query)
  end

  defp get_default_outbound_number_for_org(subdomain) do
    query =
      from(n in "numbers",
        join: o in "orgs",
        on: n.org_id == o.id,
        left_join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: o.subdomain == ^subdomain and n.is_default_outbound_number == true,
        select: %{
          id: n.id,
          number: n.number,
          name: n.name,
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
        },
        limit: 1
      )

    Repo.one(query)
  end

  # Validation functions

  defp can_make_calls(member) do
    if is_nil(member) do
      false
    else
      can_make_calls_by_org_id(member.org_id)
    end
  end

  defp can_make_calls_by_org_id(org_id) do
    # CE: no wallet/billing — gate calls only on org.is_active.
    query =
      from(o in "orgs",
        where: o.id == ^org_id,
        select: %{is_active: o.is_active}
      )

    case Repo.one(query) do
      nil -> false
      org -> org.is_active
    end
  end

  # XML response generators

  defp dial_member_dialplan(member, subdomain, context, caller) do
    # Setup via info if provided
    via_info =
      if Map.has_key?(caller, :via_number) && Map.has_key?(caller, :via_name) do
        """
        <action application="set" data="sip_h_X-Inbound-Info=:#{caller.via_number}:#{caller.via_name}"/>
        """
      else
        ""
      end

    # Setup caller ID instructions
    effect_caller_id_instructions =
      if caller.address != "" || caller.name != "" do
        """
        <action application="set" data="effective_caller_id_number=#{caller.address}"/>
        <action application="set" data="effective_caller_id_name=#{caller.name}"/>
        """
      else
        ""
      end

    # Get dial string from DialUtils
    dial_string = DialUtils.create_dial_string_for_user(member.username, subdomain)

    """
    <document type="freeswitch/xml">
      <section name="dialplan">
        <context name="#{context}">
          <extension name="dynamicMatch">
            <condition field="${comcent_context_id}" expression="^.+$" break="never">
              <action application="export" data="comcent_context_id=${comcent_context_id}"/>
              <anti-action application="export" data="comcent_context_id=${uuid}"/>
            </condition>
            <condition>
              #{init_actions(subdomain)}
              #{effect_caller_id_instructions}
              #{via_info}
              <action application="bridge" data="#{dial_string}"/>
            </condition>
          </extension>
        </context>
      </section>
    </document>
    """
  end

  defp dial_queue_dialplan(call_details) do
    # Setup via info if provided

    # TODO: If add to queue fails, we should play a recording and then hang up
    Comcent.QueueManager.add_call_to_queue(call_details)

    """
    <document type="freeswitch/xml">
      <section name="dialplan">
        <context name="public">
          <extension name="dynamicMatch">
            <condition>
              <action application="export" data="comcent_waiting_queue_id=#{call_details.queue_id}" />
              <action application="playback" data="silence_stream://-1"/>
            </condition>
          </extension>
        </context>
      </section>
    </document>
    """
  end

  defp dial_trunk_dialplan(number, to_user, subdomain) do
    # Get dial string from DialUtils
    dial_string =
      DialUtils.create_dial_string_for_sip_trunk(
        number.number,
        to_user,
        number.sip_trunk.outbound_contact
      )

    """
    <document type="freeswitch/xml">
      <section name="dialplan">
        <context name="default">
          <extension name="dynamicMatch">
            <condition field="${comcent_context_id}" expression="^.+$" break="never">
              <action application="export" data="comcent_context_id=${comcent_context_id}"/>
              <anti-action application="export" data="comcent_context_id=${uuid}"/>
            </condition>
            <condition>
              #{init_actions(subdomain)}
              <action application="set" data="effective_caller_id_number=#{number.number}"/>
              <action application="set" data="effective_caller_id_name=#{number.name}"/>
              <action application="bridge" data="#{dial_string}"/>
            </condition>
          </extension>
        </context>
      </section>
    </document>
    """
  end

  defp dial_httpapi_dialplan(to_user, subdomain) do
    """
    <document type="freeswitch/xml">
      <section name="dialplan">
        <context name="public">
          <extension name="dynamicMatch">
            <condition field="${comcent_context_id}" expression="^.+$" break="never">
              <action application="export" data="comcent_context_id=${comcent_context_id}"/>
              <anti-action application="export" data="comcent_context_id=${uuid}"/>
            </condition>
            <condition field="destination_number" match="^\\#{to_user}$">
              #{init_actions(subdomain)}
              <action application="answer" />
              <action application="log" data="******************************************** before httapi" />
              <action application="httapi" data="{method=POST}"/>
              <action application="log" data="******************************************** after httapi" />
            </condition>
          </extension>
        </context>
      </section>
    </document>
    """
  end

  defp init_actions(subdomain) do
    storage_bucket = System.get_env("STORAGE_BUCKET_NAME") || ""

    """
    <action application="export" data="comcent_subdomain=#{subdomain}" />
    <action application="export" data="comcent_recording_bucket_name=#{storage_bucket}" />
    <action application="export" data="record_pause_on_hold=false" />
    <action application="export" data="record_waste_resources=true" />
    <action application="log" data="#################################################### ${uuid}"/>
    """
  end

  defp not_allowed_response do
    """
    <document type="freeswitch/xml">
      <section name="result">
        <result status="not allowed" />
      </section>
    </document>
    """
  end
end
