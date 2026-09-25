defmodule Comcent.InstanceSetupTest do
  use Comcent.DataCase, async: false

  alias Comcent.InstanceSetup

  defp claim(token) do
    InstanceSetup.claim("Admin User", "admin@example.com", "password123", %{
      org_name: "Example Org",
      subdomain: "example",
      sip_username: "admin",
      token: token
    })
  end

  setup do
    {:ok, token} = InstanceSetup.regenerate_token!(true)
    %{token: token}
  end

  test "a wrong token returns an error instead of raising" do
    assert {:error, "Invalid setup token."} = claim("not-the-token")
    assert InstanceSetup.bootstrap_mode?()
  end

  test "the right token claims the instance once", %{token: token} do
    assert {:ok, user} = claim(token)
    assert user.is_super_admin
    refute InstanceSetup.bootstrap_mode?()

    assert {:error, "This instance has already been claimed."} = claim(token)
  end
end
