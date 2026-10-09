defmodule ComcentWeb.Internal.HttpapiNotConfiguredTest do
  @moduledoc """
  A call to a number whose flow can't route it (an imported number's empty
  flow, a start that points nowhere, a step saved without its data) must hear
  "This number is not configured" and hang up cleanly, not get a busy tone.
  """

  use ComcentWeb.ConnCase, async: false

  alias Comcent.CallFixtures
  alias Comcent.Repo
  alias Comcent.Schemas.Number

  # Obviously fake: the plug only compares them to what it is given.
  @username "test-internal-user"
  @password "test-internal-password"

  @prompt "/internal-api/prompts/number-not-configured.wav"

  setup %{conn: conn} do
    System.put_env("INTERNAL_API_USERNAME", @username)
    System.put_env("INTERNAL_API_PASSWORD", @password)

    on_exit(fn ->
      System.delete_env("INTERNAL_API_USERNAME")
      System.delete_env("INTERNAL_API_PASSWORD")
    end)

    number = CallFixtures.org() |> CallFixtures.number()
    credentials = Base.encode64("#{@username}:#{@password}")

    {:ok, conn: put_req_header(conn, "authorization", "Basic #{credentials}"), number: number}
  end

  test "an imported number's empty flow plays the prompt", ctx do
    save_flow(ctx.number, %{"nodes" => %{}, "start" => nil})
    assert_not_configured(ctx)
  end

  test "a flow that was never saved by the editor plays the prompt", ctx do
    save_flow(ctx.number, %{})
    assert_not_configured(ctx)
  end

  test "a start that points at a missing step plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("Dial", %{"to" => "1001"}, "gone"))
    assert_not_configured(ctx)
  end

  test "a Dial step with nobody to dial plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("Dial", %{"timeout" => 20}))
    assert_not_configured(ctx)
  end

  test "a Dial Group step with no numbers plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("DialGroup", %{"to" => []}))
    assert_not_configured(ctx)
  end

  test "a Queue step with no queue plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("Queue", %{}))
    assert_not_configured(ctx)
  end

  test "a Queue step whose queue was deleted plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("Queue", %{"queue" => "Nightshift"}))
    assert_not_configured(ctx)
  end

  test "a Voice Bot step with no bot plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("VoiceBot", %{"voiceBotId" => ""}))
    assert_not_configured(ctx)
  end

  test "a Play step with no audio plays the prompt", ctx do
    save_flow(ctx.number, one_step_flow("Play", %{}))
    assert_not_configured(ctx)
  end

  test "a configured Dial step still dials", ctx do
    save_flow(ctx.number, one_step_flow("Dial", %{"to" => "1001"}))

    body = ctx.conn |> inbound_call(ctx.number) |> response(200)
    assert body =~ ~s(application="bridge")
    refute body =~ @prompt
  end

  test "FreeSWITCH can fetch the prompt without credentials", %{conn: conn} do
    conn = conn |> delete_req_header("authorization") |> get(@prompt)

    assert conn.status == 200
    assert <<"RIFF", _::binary-size(4), "WAVE", _::binary>> = conn.resp_body
  end

  defp assert_not_configured(ctx) do
    body = ctx.conn |> inbound_call(ctx.number) |> response(200)

    assert body =~ ~r{<playback file="http://[^"]+#{@prompt}" />}
    assert body =~ "<hangup cause='NORMAL_CLEARING' />"
    refute body =~ "USER_BUSY"
    refute body =~ ~s(application="bridge")
  end

  defp one_step_flow(type, data, start \\ "s1") do
    %{
      "start" => start,
      "nodes" => %{
        "s1" => %{
          "id" => "s1",
          "type" => type,
          "data" => data,
          "outlets" => %{},
          "screen" => %{"x" => 0, "y" => 0}
        }
      }
    }
  end

  defp save_flow(number, graph) do
    number
    |> Ecto.Changeset.change(inbound_flow_graph: graph)
    |> Repo.update!()
  end

  defp inbound_call(conn, %Number{} = number) do
    post(conn, "/internal-api/xml-curl/httapi", %{
      "variable_sip_to_user" => number.number,
      "variable_sip_from_user" => "+13478266412",
      "variable_uuid" => Ecto.UUID.generate()
    })
  end
end
