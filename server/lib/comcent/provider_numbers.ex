defmodule Comcent.ProviderNumbers do
  @moduledoc """
  Listing and importing numbers from a connected provider account.

  There is deliberately no cached inventory of the customer's account. The
  picker fetches live, which costs one API call and is always accurate, and we
  store a row only for numbers actually imported. A cache would buy nothing —
  we already know which numbers are ours from our own tables, and drift only
  matters for numbers we manage.
  """

  require Logger

  alias Comcent.Clock
  alias Comcent.Repo
  alias Comcent.Repo.ProviderConnection, as: ProviderConnectionRepo
  alias Comcent.ProviderConnections
  alias Comcent.Schemas.{ProviderConnection, ProviderNumber}
  alias Comcent.Twilio

  @doc """
  Numbers available in the connected account, annotated for the picker.

  Each entry carries why it can or cannot be imported, so the UI never has to
  re-derive that and the two views cannot disagree.
  """
  def list_available(%ProviderConnection{} = connection) do
    imported = ProviderConnectionRepo.imported_provider_sids(connection.id)

    with {:ok, numbers} <-
           Twilio.list_incoming_phone_numbers(ProviderConnections.auth_for(connection)) do
      {:ok, Enum.map(numbers, &annotate(&1, imported))}
    end
  end

  @doc """
  Imports one number: snapshots its current provider-side config, then stores
  it as a number we manage.

  The snapshot happens **before** anything is written to the provider, and it is
  the only record of how the number looked beforehand. Associating a number with
  a trunk clears `voice_application_sid`, and detaching later restores nothing —
  so without this, disconnect cannot put the customer back where they started.

  Refuses a number already on someone else's trunk unless explicitly confirmed.
  Twilio accepts that association silently (201, no error) and steals the number
  from whatever it was serving.
  """
  def import_number(%ProviderConnection{} = connection, provider_sid, opts \\ []) do
    confirm_trunk_move? = Keyword.get(opts, :confirm_trunk_move, false)
    auth = ProviderConnections.auth_for(connection)

    with {:ok, number} <- Twilio.get_incoming_phone_number(auth, provider_sid),
         :ok <- check_voice_capable(number),
         :ok <- check_trunk_conflict(number, connection, confirm_trunk_move?) do
      insert_number(connection, number)
    end
  end

  @doc """
  Re-reads an imported number from the provider and records what changed.

  Only covers numbers we manage — a handful per customer, not their whole
  account. Returns `{:ok, :unchanged}`, `{:ok, {:drifted, fields}}` or
  `{:ok, :missing}` so the caller decides how loudly to surface it.
  """
  def refresh(%ProviderConnection{} = connection, %ProviderNumber{} = provider_number) do
    auth = ProviderConnections.auth_for(connection)

    case Twilio.get_incoming_phone_number(auth, provider_number.provider_sid) do
      {:ok, number} ->
        drifted = drifted_fields(provider_number, number)
        mark_refreshed(provider_number, number, drifted)

      {:error, {:not_found, _}} ->
        # Released in Twilio while we still route it. Mark, never delete: a
        # number vanishing out from under a live queue must surface.
        mark_missing(provider_number)

      {:error, _} = error ->
        error
    end
  end

  # --- internals -----------------------------------------------------------

  defp annotate(number, imported) do
    caps = number["capabilities"] || %{}
    sid = number["sid"]

    {importable, reason} =
      cond do
        MapSet.member?(imported, sid) -> {false, "already imported"}
        caps["voice"] != true -> {false, "no voice capability"}
        true -> {true, nil}
      end

    %{
      provider_sid: sid,
      e164: number["phone_number"],
      friendly_name: number["friendly_name"],
      capabilities: caps,
      # Surfaced so the picker can warn before we steal it from another trunk.
      trunk_sid: number["trunk_sid"],
      importable: importable,
      reason: reason
    }
  end

  defp check_voice_capable(number) do
    if get_in(number, ["capabilities", "voice"]) == true do
      :ok
    else
      {:error, {:not_voice_capable, "#{number["phone_number"]} has no voice capability"}}
    end
  end

  defp check_trunk_conflict(number, _connection, confirmed?) do
    case number["trunk_sid"] do
      nil ->
        :ok

      "" ->
        :ok

      trunk_sid ->
        if confirmed? do
          Logger.warning(
            "Importing #{number["phone_number"]} which is already on trunk #{trunk_sid} — confirmed by caller"
          )

          :ok
        else
          {:error,
           {:trunk_conflict,
            "#{number["phone_number"]} is already attached to trunk #{trunk_sid}. " <>
              "Importing it will move the number away from whatever that trunk serves."}}
        end
    end
  end

  defp insert_number(connection, number) do
    %ProviderNumber{id: Ecto.UUID.generate()}
    |> ProviderNumber.changeset(%{
      "provider_connection_id" => connection.id,
      "org_id" => connection.org_id,
      "e164" => number["phone_number"],
      "provider_sid" => number["sid"],
      "friendly_name" => number["friendly_name"],
      "capabilities" => number["capabilities"] || %{},
      "provider_metadata" => %{"trunk_sid" => number["trunk_sid"]},
      "original_config" => original_config(number),
      "last_synced_at" => Clock.naive_now(),
      "status" => "imported"
    })
    |> Repo.insert()
    |> case do
      {:ok, provider_number} ->
        {:ok, provider_number}

      {:error, changeset} ->
        # The unique index is the race-safe check for "already imported", so it
        # is load-bearing rather than a backstop -- two operators importing the
        # same number at once reach it. But its raw message reads
        # "provider_connection_id: has already been taken", which tells the
        # customer nothing, so it is translated here at the point where the
        # phone number is still in hand.
        if already_imported?(changeset) do
          {:error,
           {:already_imported,
            "#{number["phone_number"]} has already been imported from this account"}}
        else
          {:error, changeset}
        end
    end
  end

  defp already_imported?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:provider_connection_id, {_msg, opts}} ->
        opts[:constraint] == :unique

      _ ->
        false
    end)
  end

  # Exactly the fields Comcent may overwrite. Anything we do not touch does not
  # need restoring, and storing less keeps the snapshot meaningful.
  defp original_config(number) do
    Map.take(number, [
      "trunk_sid",
      "voice_url",
      "voice_method",
      "voice_fallback_url",
      "voice_fallback_method",
      "voice_application_sid",
      "sms_url",
      "sms_method",
      "sms_fallback_url",
      "sms_fallback_method",
      "sms_application_sid",
      "status_callback",
      "status_callback_method"
    ])
  end

  # Compares the fields provisioning actually sets. The trunk is the one that
  # breaks calls, but a repointed voice_url or status_callback is exactly the
  # "changed in Twilio since we configured it" the UI promises to detect, and
  # comparing only the trunk quietly reported those as healthy.
  @watched_fields ["voice_url", "voice_method", "voice_fallback_url", "status_callback"]

  defp drifted_fields(%ProviderNumber{} = stored, number) do
    metadata = stored.provider_metadata || %{}
    expected_trunk = metadata["comcent_trunk_sid"]
    original = stored.original_config || %{}

    trunk_drift =
      if is_nil(expected_trunk) do
        # No recorded expectation means provisioning never got as far as
        # writing one. Reporting "no drift" there is a false clean bill of
        # health for the one field that decides whether calls arrive.
        [%{field: "trunk_sid", expected: :unknown, actual: number["trunk_sid"]}]
      else
        maybe_drift([], "trunk_sid", expected_trunk, number["trunk_sid"])
      end

    Enum.reduce(@watched_fields, trunk_drift, fn field, acc ->
      # Compared against the snapshot: these are the values we left in place,
      # so a difference means someone changed them in the provider console.
      maybe_drift(acc, field, Map.get(original, field), Map.get(number, field))
    end)
    |> Enum.reverse()
  end

  defp maybe_drift(acc, _field, nil, _actual), do: acc
  defp maybe_drift(acc, _field, expected, actual) when expected == actual, do: acc

  defp maybe_drift(acc, field, expected, actual),
    do: [%{field: field, expected: expected, actual: actual} | acc]

  defp mark_refreshed(provider_number, number, drifted) do
    attrs = %{
      "capabilities" => number["capabilities"] || %{},
      "provider_metadata" =>
        Map.merge(provider_number.provider_metadata || %{}, %{
          "trunk_sid" => number["trunk_sid"],
          "drifted" => drifted != [],
          "drifted_fields" => drifted
        }),
      "last_synced_at" => Clock.naive_now(),
      "status" => "imported"
    }

    with {:ok, updated} <- provider_number |> ProviderNumber.changeset(attrs) |> Repo.update() do
      if drifted == [], do: {:ok, :unchanged}, else: {:ok, {:drifted, drifted, updated}}
    end
  end

  defp mark_missing(provider_number) do
    with {:ok, _} <-
           provider_number
           |> ProviderNumber.changeset(%{
             "status" => "missing",
             "last_synced_at" => Clock.naive_now()
           })
           |> Repo.update() do
      {:ok, :missing}
    end
  end
end
