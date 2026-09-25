defmodule Comcent.MailerConfigTest do
  use ExUnit.Case, async: true

  # config/runtime.exs runs after config/test.exs; it must not swap the test
  # adapter for SMTP, or tests send real SMTP traffic and can't assert on mail.
  test "tests deliver mail through Swoosh's test adapter" do
    assert Application.fetch_env!(:comcent, Comcent.Mailer)[:adapter] == Swoosh.Adapters.Test
  end
end
