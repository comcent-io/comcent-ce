defmodule ComcentWeb.Internal.HttpapiVoiceBotTest do
  @moduledoc """
  A call routed into a voice bot step of a number's inbound flow must be
  bridged to that bot. The flow is stored the way it was saved, so the voice
  bot node's id can be spelled `voiceBotId` (the flow editor sends the flow as
  a JSON string, which is stored untouched) or `voice_bot_id` (a flow sent as
  a JSON object is snake_cased by the request decoder). Both must work.
  """

  use ComcentWeb.ConnCase, async: false

  alias Comcent.RedisClient
  alias Comcent.Repo
  alias Comcent.Schemas.{Number, Org, SipTrunk, VoiceBot}

  # Obviously fake: the plug only compares them to what it is given.
  @username "test-internal-user"
  @password "test-internal-password"

  # A documentation address (RFC 5737), registered as the only voice bot host.
  @voice_bot_ip_key "voice.bot.ip.192.0.2.10"

  setup %{conn: conn} do
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)
    {:ok, _} = RedisClient.set(@voice_bot_ip_key, "1")

    on_exit(fn ->
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
      RedisClient.del(@voice_bot_ip_key)
    end)

    org =
      Repo.insert!(%Org{
        id: Ecto.UUID.generate(),
        name: "Acme",
        subdomain: "acme-#{unique()}",
        use_custom_domain: false,
        assign_ext_automatically: false,
        is_active: true
      })

    trunk =
      Repo.insert!(%SipTrunk{
        id: Ecto.UUID.generate(),
        org_id: org.id,
        name: "Trunk",
        outbound_contact: "trunk.example.com"
      })

    number =
      Repo.insert!(%Number{
        id: Ecto.UUID.generate(),
        name: "Main",
        number: "+1347826#{1000 + rem(unique(), 9000)}",
        org_id: org.id,
        sip_trunk_id: trunk.id,
        inbound_flow_graph: %{}
      })

    voice_bot =
      Repo.insert!(%VoiceBot{
        id: Ecto.UUID.generate(),
        org_id: org.id,
        name: "Receptionist",
        instructions: "Answer the phone.",
        not_to_do_instructions: "",
        api_key: "test-voice-bot-key",
        pipeline: "test",
        queues: []
      })

    credentials = Base.encode64("#{@username}:#{@password}")

    {:ok,
     conn: put_req_header(conn, "authorization", "Basic #{credentials}"),
     number: number,
     voice_bot: voice_bot}
  end

  test "bridges to the bot of a flow saved by the editor (voiceBotId)", ctx do
    graph = voice_bot_flow(%{"voiceBotName" => "Receptionist", "voiceBotId" => ctx.voice_bot.id})
    # The editor sends the flow as a JSON string, which is stored as written.
    save_flow(ctx.number, Jason.encode!(graph))

    assert stored_voice_bot_node(ctx.number)["data"]["voiceBotId"] == ctx.voice_bot.id

    body = ctx.conn |> inbound_call(ctx.number) |> response(200)
    assert body =~ ~s(application="bridge")
    assert body =~ "sip:#{ctx.voice_bot.id}@"
  end

  test "bridges to the bot of a flow saved as a JSON object (voice_bot_id)", ctx do
    graph = voice_bot_flow(%{"voiceBotName" => "Receptionist", "voiceBotId" => ctx.voice_bot.id})
    # A flow sent as a JSON object is snake_cased by the request decoder.
    save_flow(ctx.number, ComcentWeb.JsonCase.snake_case_keys(graph))

    assert stored_voice_bot_node(ctx.number)["data"]["voice_bot_id"] == ctx.voice_bot.id

    body = ctx.conn |> inbound_call(ctx.number) |> response(200)
    assert body =~ ~s(application="bridge")
    assert body =~ "sip:#{ctx.voice_bot.id}@"
  end

  test "hangs up when the voice bot step has no bot chosen", ctx do
    save_flow(ctx.number, Jason.encode!(voice_bot_flow(%{"voiceBotId" => ""})))

    body = ctx.conn |> inbound_call(ctx.number) |> response(200)
    assert body =~ "hangup"
    refute body =~ ~s(application="bridge")
  end

  defp voice_bot_flow(data) do
    %{
      "start" => "vb1",
      "nodes" => %{
        "vb1" => %{
          "id" => "vb1",
          "type" => "VoiceBot",
          "data" => data,
          "outlets" => %{},
          "screen" => %{"x" => 0, "y" => 0}
        }
      }
    }
  end

  defp save_flow(number, graph) do
    number
    |> Number.changeset(%{"inbound_flow_graph" => graph})
    |> Repo.update!()
  end

  defp stored_voice_bot_node(number) do
    Repo.get!(Number, number.id).inbound_flow_graph["nodes"]["vb1"]
  end

  defp inbound_call(conn, number) do
    post(conn, "/internal-api/xml-curl/httapi", %{
      "variable_sip_to_user" => number.number,
      "variable_sip_from_user" => "+13478266412",
      "variable_uuid" => Ecto.UUID.generate()
    })
  end

  defp unique, do: System.unique_integer([:positive])
end
