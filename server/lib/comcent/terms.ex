defmodule Comcent.Terms do
  @moduledoc """
  The Terms of Use and Privacy Policy a user accepts before using the app.

  They are configuration (TERMS_URL, PRIVACY_URL, TERMS_VERSION in
  config/runtime.exs), not code, because whether users accept any terms, and
  which, is the operator's call: with TERMS_URL unset nobody is asked. Each
  acceptance records the version accepted, so publishing new terms under a
  new version asks everyone again.
  """

  alias Comcent.Schemas.User

  @doc "The terms in force, or nil when this deployment has none."
  def current do
    config = Application.get_env(:comcent, :terms, [])

    if config[:terms_url] do
      %{
        terms_url: config[:terms_url],
        privacy_url: config[:privacy_url],
        version: config[:version]
      }
    end
  end

  @doc "The version a user accepting now agrees to; nil when there are no terms."
  def current_version do
    case current() do
      nil -> nil
      terms -> terms.version
    end
  end

  @doc """
  Whether the user has yet to accept the terms in force. A user who accepted
  before terms had versions has a nil version and is asked again: the page
  they accepted linked to placeholders.
  """
  def acceptance_required?(%User{} = user) do
    case current() do
      nil -> false
      terms -> user.accepted_terms_version != terms.version
    end
  end

  @doc """
  What the web app needs to send the user to the terms page and render it, or
  nil when there are no terms. `previously_accepted` tells a new user from one
  being asked again after the terms changed.
  """
  def for_user(%User{} = user) do
    case current() do
      nil ->
        nil

      terms ->
        Map.merge(terms, %{
          acceptance_required: acceptance_required?(user),
          previously_accepted: user.has_agreed_to_tos
        })
    end
  end
end
