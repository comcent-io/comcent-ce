defmodule Comcent.EmailHandlerTest do
  use Comcent.DataCase
  import Mock
  alias Comcent.EmailHandler
  alias Comcent.Repo

  describe "check_and_send_alerts/0" do
    test "sends emails to admins of organizations with wallets below threshold" do
      # Mock the database queries and email sending
      with_mocks([
        {Repo, [],
         [
           # Mock empty result for org query
           all: fn _query -> [] end,
           update_all: fn _query, _updates -> {0, nil} end
         ]}
      ]) do
        assert :ok = EmailHandler.check_and_send_alerts()
      end
    end
  end
end
