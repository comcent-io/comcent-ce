defmodule ComcentWeb.Internal.ConfigurationController do
  use ComcentWeb, :controller
  require Logger

  def create(conn, params) do
    Logger.info("Received POST request to /internal/configuration")
    Logger.info("params: #{inspect(params)}")

    key_value = params["key_value"]
    Logger.info("keyValue: #{key_value}")

    response = generate_configuration(params)

    Logger.info("Response: #{response}\n\n")

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, response)
  end

  defp generate_configuration(%{"key_value" => "amqp.conf"}) do
    rabbitmq_config = Application.get_env(:comcent, :rabbitmq)
    rabbitmq_url = rabbitmq_config[:url] || ""

    %{username: username, password: password, hostname: hostname, port: port} =
      parse_rabbitmq_url(rabbitmq_url)

    ssl_params =
      if String.starts_with?(rabbitmq_url, "amqps") do
        """
        <param name="ssl_on" value="true"/>
        <param name="ssl_verify_peer" value="false"/>
        """
      else
        ""
      end

    """
    <document type="freeswitch/xml">
      <section name="configuration">
        <configuration name="amqp.conf" description="mod_amqp">
          <producers>
              <profile name="default">
                  <connections>
                      <connection name="primary">
                          <param name="hostname" value="#{hostname}"/>
                          <param name="virtualhost" value="/"/>
                          <param name="username" value="#{username}"/>
                          <param name="password" value="#{password}"/>
                          <param name="port" value="#{port}"/>
                          <param name="heartbeat" value="0"/>
                          #{ssl_params}
                      </connection>
                  </connections>
                  <params>
                      <param name="exchange-name" value="TAP.Events"/>
                      <param name="exchange-type" value="topic"/>
                      <param name="circuit_breaker_ms" value="10000"/>
                      <param name="reconnect_interval_ms" value="1000"/>
                      <param name="send_queue_size" value="5000"/>
                      <param name="enable_fallback_format_fields" value="1"/>
                      <!-- The routing key is made from the format string, using the header values in the event specified in the format_fields.-->
                      <!-- Fields that are prefixed with a # are treated as literals rather than doing a header lookup -->
                      <param name="format_fields"
                             value="#FreeSWITCH,FreeSWITCH-Hostname,Event-Name,Event-Subclass,Unique-ID"/>
                      <param name="event_filter" value="SWITCH_EVENT_CHANNEL_CREATE,SWITCH_EVENT_CHANNEL_DESTROY,SWITCH_EVENT_CHANNEL_ANSWER,SWITCH_EVENT_CHANNEL_HOLD,SWITCH_EVENT_CHANNEL_UNHOLD,SWITCH_EVENT_RECORD_START,SWITCH_EVENT_RECORD_STOP,SWITCH_EVENT_HEARTBEAT,SWITCH_EVENT_CUSTOM"/>
                  </params>
              </profile>
          </producers>
          <commands>
              <profile name="default">
                  <connections>
                      <connection name="primary">
                          <param name="hostname" value="#{hostname}"/>
                          <param name="virtualhost" value="/"/>
                          <param name="username" value="#{username}"/>
                          <param name="password" value="#{password}"/>
                          <param name="port" value="#{port}"/>
                          <param name="heartbeat" value="0"/>
                          #{ssl_params}
                      </connection>
                  </connections>
                  <params>
                      <param name="exchange-name" value="TAP.Commands"/>
                      <param name="binding_key" value="commandBindingKey"/>
                      <param name="reconnect_interval_ms" value="1000"/>
                      <param name="queue-passive" value="false"/>
                      <param name="queue-durable" value="false"/>
                      <param name="queue-exclusive" value="false"/>
                      <param name="queue-auto-delete" value="true"/>
                  </params>
              </profile>
          </commands>
        </configuration>
      </section>
    </document>
    """
  end

  defp generate_configuration(%{"key_value" => "acl.conf"}) do
    # The "private" list is referenced by the internal sofia profile's
    # local-network-acl. ALLOWED → FS treats the destination as local and uses
    # rtp-ip (private bind) in SDP. DENIED → FS uses ext-rtp-ip.
    #
    # Order matters (FreeSWITCH stops at the first matching node):
    #   1. SBC IP — denied first so a wider FS_LOCAL_NETWORK CIDR can't
    #      accidentally allow it.
    #   2. FS_LOCAL_NETWORK CIDRs — explicit allows for the docker subnet (or
    #      whatever LAN FreeSWITCH and trunk peers share).
    #   3. Default "allow" catches everything else, so unmarked peers still
    #      reach FS over symmetric-RTP / NAT-detected paths the same as before.
    sbc_deny =
      case System.get_env("SBC_IP") do
        nil -> ""
        "" -> ""
        entry ->
          cidr = if String.contains?(entry, "/"), do: entry, else: "#{entry}/32"
          ~s(<node type="deny" cidr="#{cidr}"/>)
      end

    fs_local_allows =
      (System.get_env("FS_LOCAL_NETWORK") || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&~s(<node type="allow" cidr="#{&1}"/>))
      |> Enum.join("\n              ")

    """
    <document type="freeswitch/xml">
      <section name="configuration">
        <configuration name="acl.conf" description="Network Lists">
          <network-lists>
            <list name="deny" default="deny"></list>
            <list name="private" default="deny">
              #{sbc_deny}
              #{fs_local_allows}
            </list>
          </network-lists>
        </configuration>
      </section>
    </document>
    """
  end

  defp generate_configuration(%{"key_value" => "event_socket.conf"}) do
    """
    <document type="freeswitch/xml">
      <section name="configuration">
        <configuration name="event_socket.conf" description="Socket Client">
          <settings>
            <param name="nat-map" value="false"/>
            <param name="listen-ip" value="0.0.0.0"/>
            <param name="listen-port" value="8021"/>
            <param name="password" value="ClueCon"/>
            <param name="apply-inbound-acl" value="private"/>
            <!--<param name="stop-on-bind-error" value="true"/>-->
          </settings>
        </configuration>
      </section>
    </document>
    """
  end

  defp generate_configuration(_params) do
    not_found_response()
  end

  defp parse_rabbitmq_url(rabbitmq_url) do
    [_protocol, main_url] = String.split(rabbitmq_url, "://", parts: 2)
    url = URI.parse("https://#{main_url}")

    %{
      username: url.userinfo |> String.split(":") |> List.first() || "",
      password: url.userinfo |> String.split(":") |> List.last() || "",
      hostname: url.host || "",
      port: "5672"
    }
  end

  defp not_found_response do
    """
    <document type="freeswitch/xml">
      <section name="result">
        <result status="not found" />
      </section>
    </document>
    """
  end
end
