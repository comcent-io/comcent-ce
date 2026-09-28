defmodule ComcentWeb.TermsTest do
  @moduledoc """
  The terms step comes from configuration: no TERMS_URL means no
  one is asked, and a user is asked again whenever the version they accepted
  isn't TERMS_VERSION, including users who accepted before there were
  versions.
  """

  use ComcentWeb.ConnCase, async: false

  alias Comcent.{Auth, Repo}
  alias Comcent.Schemas.User

  @terms [
    terms_url: "https://terms.example.com/terms-of-use",
    privacy_url: "https://terms.example.com/privacy-policy",
    version: "2026-09-28"
  ]

  setup do
    previous_key = System.get_env("SIGNING_KEY")
    System.put_env("SIGNING_KEY", "test-signing-key")
    previous_terms = Application.get_env(:comcent, :terms)

    on_exit(fn ->
      if previous_key,
        do: System.put_env("SIGNING_KEY", previous_key),
        else: System.delete_env("SIGNING_KEY")

      Application.put_env(:comcent, :terms, previous_terms || [])
    end)

    :ok
  end

  defp configure_terms(terms), do: Application.put_env(:comcent, :terms, terms)

  defp user(attrs \\ []) do
    Repo.insert!(
      struct(
        %User{
          id: Ecto.UUID.generate(),
          name: "Dana Whitfield",
          email: "dana.#{System.unique_integer([:positive])}@example.com",
          is_email_verified: true
        },
        attrs
      )
    )
  end

  defp authed(conn, user) do
    put_req_header(conn, "authorization", "Bearer #{Auth.sign_session_token(user, "password")}")
  end

  defp session(conn, user) do
    conn |> authed(user) |> get("/api/v2/user/session") |> json_response(200)
  end

  defp accept(conn, user) do
    conn |> authed(user) |> post("/api/v2/user/accept-terms", %{}) |> json_response(200)
  end

  test "with no TERMS_URL nobody is asked to accept anything", %{conn: conn} do
    configure_terms(terms_url: nil, privacy_url: nil, version: nil)

    assert %{"terms" => nil} = session(conn, user())
  end

  test "a new user is asked, with the configured links and version", %{conn: conn} do
    configure_terms(@terms)

    assert session(conn, user())["terms"] == %{
             "termsUrl" => "https://terms.example.com/terms-of-use",
             "privacyUrl" => "https://terms.example.com/privacy-policy",
             "version" => "2026-09-28",
             "acceptanceRequired" => true,
             "previouslyAccepted" => false
           }
  end

  test "accepting records the version in force and stops the asking", %{conn: conn} do
    configure_terms(@terms)
    user = user()

    assert %{"success" => true} = accept(conn, user)

    stored = Repo.get!(User, user.id)
    assert stored.accepted_terms_version == "2026-09-28"
    assert stored.has_agreed_to_tos
    assert stored.agreed_to_tos_at

    assert %{"acceptanceRequired" => false} = session(build_conn(), stored)["terms"]
  end

  test "a new version asks a user who accepted the old one again", %{conn: conn} do
    configure_terms(@terms)

    user =
      user(
        has_agreed_to_tos: true,
        agreed_to_tos_at: ~U[2026-09-01 00:00:00Z],
        accepted_terms_version: "2026-09-01"
      )

    assert %{"acceptanceRequired" => true, "previouslyAccepted" => true} =
             session(conn, user)["terms"]
  end

  test "a user who accepted before terms had versions is asked again", %{conn: conn} do
    configure_terms(@terms)
    user = user(has_agreed_to_tos: true, agreed_to_tos_at: ~U[2026-03-15 00:00:00Z])

    assert %{"acceptanceRequired" => true, "previouslyAccepted" => true} =
             session(conn, user)["terms"]
  end
end
