defmodule ComcentWeb.Internal.DirectoryController do
  use ComcentWeb, :controller
  require Logger
  import Ecto.Query

  def create(conn, params) do
    Logger.info("Received POST request to /internal/directory")
    Logger.info("params: #{inspect(params)}")

    username = params["user"]
    domain = params["domain"]
    purpose = params["purpose"]
    profile = params["profile"]

    Logger.info("purpose: #{purpose}, profile: #{profile}, user: #{username}, domain: #{domain}")

    if is_nil(username) or is_nil(domain) do
      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, not_found_response())
    else
      sip_domain = Application.fetch_env!(:comcent, :sip_domain)

      if !String.ends_with?(domain, sip_domain) do
        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, not_found_response())
      else
        domain_parts = String.split(domain, ".")

        if length(domain_parts) != 3 do
          conn
          |> put_resp_content_type("text/xml")
          |> send_resp(200, not_found_response())
        else
          [subdomain | _] = domain_parts

          member =
            from(m in "org_members",
              join: o in "orgs",
              on: m.org_id == o.id,
              join: u in "users",
              on: m.user_id == u.id,
              where: m.username == ^username and o.subdomain == ^subdomain,
              select: %{
                username: m.username,
                sip_password: m.sip_password,
                name: u.name
              }
            )
            |> Comcent.Repo.one()

          if is_nil(member) do
            conn
            |> put_resp_content_type("text/xml")
            |> send_resp(200, not_found_response())
          else
            response = """
            <document type='freeswitch/xml'>
              <section name='directory'>
                <domain name='#{domain}'>
                  <params>
                    <param name='dial-string' value='{^^:sip_invite_domain=${dialed_domain}:presence_id=${dialed_user}@${dialed_domain}}${sofia_contact(*/${dialed_user}@${dialed_domain})},${verto_contact(${dialed_user}@${dialed_domain})}'/>
                    <param name='jsonrpc-allowed-methods' value='verto'/>
                  </params>
                  <user id='#{username}'>
                    <params>
                      <param name='password' value='#{member.sip_password}'/>
                    </params>
                    <variables>
                      <variable name='user_context' value='default'/>
                      <variable name='effective_caller_id_name' value='#{member.name}'/>
                      <variable name='effective_caller_id_number' value='#{member.username}'/>
                    </variables>
                  </user>
                </domain>
              </section>
            </document>
            """

            conn
            |> put_resp_content_type("text/xml")
            |> send_resp(200, response)
          end
        end
      end
    end
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
