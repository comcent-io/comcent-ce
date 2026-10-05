defmodule Comcent.TwilioTest do
  use ExUnit.Case, async: true

  alias Comcent.Twilio

  describe "valid_signature?/4" do
    # Twilio's own documented example, from the webhook security guide. Keeping
    # it as a golden vector means a refactor of the payload construction cannot
    # quietly break signature validation.
    @url "https://mycompany.com/myapp.php?foo=1&bar=2"
    @params %{
      "CallSid" => "CA1234567890ABCDE",
      "Caller" => "+14158675309",
      "Digits" => "1234",
      "From" => "+14158675309",
      "To" => "+18005551212"
    }
    @token "12345"
    @signature "RSOYDt4T1cUTdK1PDd93/VVr8B8="

    test "accepts Twilio's documented example" do
      assert Twilio.valid_signature?(@signature, @url, @params, @token)
    end

    test "is independent of map ordering" do
      reordered = @params |> Enum.reverse() |> Map.new()
      assert Twilio.valid_signature?(@signature, @url, reordered, @token)
    end

    test "rejects a tampered parameter" do
      tampered = Map.put(@params, "To", "+19998887777")
      refute Twilio.valid_signature?(@signature, @url, tampered, @token)
    end

    test "rejects an added parameter" do
      extra = Map.put(@params, "Injected", "1")
      refute Twilio.valid_signature?(@signature, @url, extra, @token)
    end

    test "rejects a different URL" do
      refute Twilio.valid_signature?(@signature, "https://evil.example.com/", @params, @token)
    end

    test "rejects the wrong auth token" do
      refute Twilio.valid_signature?(@signature, @url, @params, "54321")
    end

    test "rejects a garbage signature" do
      refute Twilio.valid_signature?("not-a-signature", @url, @params, @token)
    end

    test "returns false rather than raising on non-binary input" do
      refute Twilio.valid_signature?(nil, @url, @params, @token)
      refute Twilio.valid_signature?(@signature, @url, @params, nil)
    end

    test "handles a request with no parameters" do
      signature = :crypto.mac(:hmac, :sha, @token, @url) |> Base.encode64()
      assert Twilio.valid_signature?(signature, @url, %{}, @token)
    end
  end
end
