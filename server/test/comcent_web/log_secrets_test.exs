defmodule ComcentWeb.LogSecretsTest do
  @moduledoc """
  Secrets are never logged: not the session token a browser connects its
  WebSocket with, not the RabbitMQ password in FreeSWITCH's amqp.conf, not
  an agent's SIP password from the directory.
  """

  # Not async: raises the log level and swaps app and env config.
  use ComcentWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  require Phoenix.ChannelTest

  alias Comcent.{ProviderFixtures, Repo}
  alias Comcent.Schemas.{OrgMember, User}

  @endpoint ComcentWeb.Endpoint
  @username "test-internal-user"
  @password "test-internal-password"

  setup %{conn: conn} do
    # The test config logs warnings only; these lines log at info.
    level = Logger.level()
    Logger.configure(level: :info)
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)

    on_exit(fn ->
      Logger.configure(level: level)
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
    end)

    credentials = Base.encode64("#{@username}:#{@password}")
    {:ok, internal: put_req_header(conn, "authorization", "Basic #{credentials}")}
  end

  test "a WebSocket connect doesn't log the session token" do
    token = "eyJhbGciOiJIUzI1NiJ9.session-token-7q2x"

    log =
      capture_log(fn ->
        Phoenix.ChannelTest.connect(ComcentWeb.WebSocket, %{
          "subdomain" => "acme",
          "token" => token
        })
      end)

    refute log =~ "session-token-7q2x"
  end

  test "FreeSWITCH gets amqp.conf with the RabbitMQ password, which isn't logged", ctx do
    original = Application.get_env(:comcent, :rabbitmq)

    Application.put_env(
      :comcent,
      :rabbitmq,
      Keyword.put(original || [], :url, "amqp://comcent:rabbit-pw-9f3k@rabbitmq:5672")
    )

    on_exit(fn -> Application.put_env(:comcent, :rabbitmq, original) end)

    {conn, log} =
      with_log(fn ->
        post(ctx.internal, "/internal-api/xml-curl/configuration", %{"key_value" => "amqp.conf"})
      end)

    assert response(conn, 200) =~ "rabbit-pw-9f3k"
    refute log =~ "rabbit-pw-9f3k"
    assert log =~ "FreeSWITCH configuration requested: amqp.conf"
  end

  test "the directory answers with the agent's SIP password, which isn't logged", ctx do
    org = ProviderFixtures.org()

    user =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        name: "Tova Lindqvist",
        email: "tova.#{System.unique_integer([:positive])}@example.com",
        is_email_verified: true
      })

    Repo.insert!(%OrgMember{
      user_id: user.id,
      org_id: org.id,
      role: :MEMBER,
      username: "tova",
      sip_password: "sip-pw-4m8z",
      presence: "Available"
    })

    domain = "#{org.subdomain}.#{Application.fetch_env!(:comcent, :sip_user_root_domain)}"

    {conn, log} =
      with_log(fn ->
        post(ctx.internal, "/internal-api/xml-curl/directory", %{
          "user" => "tova",
          "domain" => domain
        })
      end)

    assert response(conn, 200) =~ "sip-pw-4m8z"
    refute log =~ "sip-pw-4m8z"
  end
end
