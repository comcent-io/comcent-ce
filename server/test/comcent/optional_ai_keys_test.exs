defmodule Comcent.OptionalAiKeysTest do
  @moduledoc """
  DEEPGRAM_API_KEY and OPENAI_API_KEY are optional: with no key, the AI
  steps that need it are skipped instead of calling the API without a key.
  """

  # Not async: swaps application config.
  use ExUnit.Case, async: false

  setup do
    deepgram = Application.get_env(:comcent, :deepgram)
    openai = Application.get_env(:comcent, :openai)

    on_exit(fn ->
      Application.put_env(:comcent, :deepgram, deepgram)
      Application.put_env(:comcent, :openai, openai)
    end)
  end

  test "a key counts as configured only when it is set and not blank" do
    for {module, app_key} <- [{Comcent.Deepgram, :deepgram}, {Comcent.OpenAI, :openai}] do
      Application.put_env(:comcent, app_key, base_url: "https://example.test")
      refute module.configured?()

      Application.put_env(:comcent, app_key, api_key: "", base_url: "https://example.test")
      refute module.configured?()

      Application.put_env(:comcent, app_key, api_key: "k-123", base_url: "https://example.test")
      assert module.configured?()
    end
  end

  test "the daily summary job does nothing without an OpenAI key" do
    Application.put_env(:comcent, :openai, base_url: "https://example.test")
    assert Comcent.DailySummary.generate_daily_summaries() == :ok
  end
end
