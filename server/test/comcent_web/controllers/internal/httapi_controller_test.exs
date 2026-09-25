defmodule ComcentWeb.Internal.HttpapiControllerTest do
  use ExUnit.Case, async: false
  alias ComcentWeb.Internal.HttpapiController

  describe "convert_media_to_http/1" do
    setup do
      original = Application.fetch_env!(:comcent, :internal_api_base_url)
      on_exit(fn -> Application.put_env(:comcent, :internal_api_base_url, original) end)
    end

    test "turns an uploaded prompt's s3 path into an absolute internal playback URL" do
      Application.put_env(:comcent, :internal_api_base_url, "http://server:4000/internal-api")

      assert HttpapiController.convert_media_to_http("s3://bucket/acme/playback/welcome.wav") ==
               "http://server:4000/internal-api/playback/acme/welcome.wav"
    end

    test "leaves non-s3 media untouched" do
      assert HttpapiController.convert_media_to_http("ivr/ivr-welcome.wav") ==
               "ivr/ivr-welcome.wav"
    end

    test "returns an empty string for nil" do
      assert HttpapiController.convert_media_to_http(nil) == ""
    end
  end

  test "the internal API base URL is configured and absolute" do
    assert Application.fetch_env!(:comcent, :internal_api_base_url) =~ ~r{^https?://}
  end
end
