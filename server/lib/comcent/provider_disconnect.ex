defmodule Comcent.ProviderDisconnect do
  @moduledoc """
  Undoing a provider connection.

  Connecting is not a one-way door. Importing a number moves it onto a Comcent
  trunk and clears its `voice_application_sid`, and Twilio does that silently —
  so leaving without a restore would strand the customer with numbers pointing
  at us and no record of how they were configured before.

  `provider_numbers.original_config`, captured at import before the first write,
  is that record. This module puts it back.

  Two modes, because they are different intentions and guessing would be wrong:

    * `:release` — restore the provider-side configuration and remove Comcent's
      rows. The customer is leaving.
    * `:keep` — leave the provider alone and mark our rows inactive. The
      customer is pausing, or moving numbers between connections.
  """

  require Logger

  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.ProviderConnections
  alias Comcent.Repo.ProviderConnection, as: ProviderConnectionRepo
  alias Comcent.Schemas.{Number, NumberChannel, ProviderConnection, ProviderNumber, SipTrunk}
  alias Comcent.Twilio

  @doc """
  Reports what disconnecting would affect, so the customer decides with the
  facts in front of them rather than after the fact.

  Numbers attached to a live queue, campaign or flow are called out separately:
  those are the ones where disconnecting interrupts something running.
  """
  def preview(%ProviderConnection{} = connection) do
    numbers = ProviderConnectionRepo.get_numbers(connection.id)
    provider_sids = Enum.map(numbers, & &1.id)

    comcent_numbers =
      from(n in Number,
        where: n.provider_number_id in ^provider_sids,
        preload: [:campaigns]
      )
      |> Repo.all()

    in_use =
      Enum.filter(comcent_numbers, fn n ->
        n.campaigns != [] or has_flow?(n)
      end)

    # A campaign holds the number with an ON DELETE RESTRICT foreign key, so it
    # does not merely warn -- release cannot proceed until it is detached. A
    # flow is only a warning: it deletes cleanly.
    blocked = Enum.filter(comcent_numbers, &(&1.campaigns != []))

    %{
      connection_id: connection.id,
      label: connection.label,
      number_count: length(numbers),
      numbers: Enum.map(numbers, & &1.e164),
      in_use: Enum.map(in_use, & &1.number),
      blocked: Enum.map(blocked, & &1.number),
      restorable: Enum.count(numbers, &(&1.original_config not in [nil, %{}]))
    }
  end

  @doc """
  Disconnects. `mode` is `:release` or `:keep`.

  Restore is best effort and reported rather than fatal: the provider may have
  moved on — a number released, a trunk deleted by hand — and refusing to
  disconnect because one number cannot be restored would trap the customer in
  the connection they are trying to leave.
  """
  def disconnect(%ProviderConnection{} = connection, mode) when mode in [:release, :keep] do
    # Reloaded for the same reason provisioning reloads: provisioning writes the
    # trunk onto the connection, so a caller holding an older struct would see
    # no trunk and quietly skip deleting it, leaving an orphan behind.
    connection = Repo.get(ProviderConnection, connection.id) || connection
    numbers = ProviderConnectionRepo.get_numbers(connection.id)

    if mode == :keep do
      deactivate(connection, numbers)
      {:ok, %{mode: mode, numbers: length(numbers), restored: 0, failed: []}}
    else
      release(connection, numbers)
    end
  end

  defp release(connection, numbers) do
    # Checked before anything is touched in the provider account. Deleting the
    # rows is not guaranteed to succeed -- a number referenced by a campaign is
    # ON DELETE RESTRICT -- and discovering that after the trunk is gone leaves
    # the customer with a deleted trunk and Comcent rows still pointing at it.
    case blockers(numbers) do
      [] ->
        auth = ProviderConnections.auth_for(connection)
        restore_results = Enum.map(numbers, &restore_number(auth, &1))
        teardown_provider_trunk(connection)

        case Repo.transaction(fn -> remove_comcent_rows(connection, numbers) end) do
          {:ok, _} ->
            {:ok,
             %{
               mode: :release,
               numbers: length(numbers),
               restored: Enum.count(restore_results, & &1.ok),
               failed: Enum.reject(restore_results, & &1.ok)
             }}

          {:error, reason} ->
            {:error, {:disconnect_failed, "Could not remove the numbers: #{inspect(reason)}"}}
        end

      blocked ->
        {:error,
         {:numbers_in_use,
          "These numbers are still used by a campaign and must be detached first: " <>
            Enum.join(blocked, ", ")}}
    end
  end

  # Only campaigns block: the FK refuses the delete. A number with an inbound
  # flow is warned about in `preview/1` but deletes cleanly.
  defp blockers(provider_numbers) do
    ids = Enum.map(provider_numbers, & &1.id)

    from(n in Number, where: n.provider_number_id in ^ids, preload: [:campaigns])
    |> Repo.all()
    |> Enum.filter(&(&1.campaigns != []))
    |> Enum.map(& &1.number)
  end

  @doc """
  Releases a single imported number: restores its provider-side configuration
  and removes the record that marks it as managed by Comcent.

  Used when a customer deletes one number rather than the whole connection.
  Without this, deleting a number in Comcent leaves it attached to a Comcent
  trunk in the provider account — still routed to a trunk the customer can no
  longer see or manage — and leaves the `provider_numbers` row behind, which
  makes the number look "already imported" and blocks re-importing it.

  Restore failure is reported, not fatal. The provider may have moved on, and
  refusing to delete a number from Comcent because Twilio would not cooperate
  would leave the customer stuck with a row they cannot remove.
  """
  def release_number(%ProviderNumber{} = provider_number) do
    connection = Repo.get(ProviderConnection, provider_number.provider_connection_id)

    result =
      if connection do
        restore_number(ProviderConnections.auth_for(connection), provider_number)
      else
        %{e164: provider_number.e164, ok: false, error: "connection no longer exists"}
      end

    Repo.delete(provider_number)
    {:ok, result}
  end

  # --- provider side -------------------------------------------------------

  defp restore_number(auth, %ProviderNumber{original_config: original} = provider_number)
       when is_map(original) and original != %{} do
    params = restore_params(original)

    case Twilio.update_incoming_phone_number(auth, provider_number.provider_sid, params) do
      {:ok, updated} ->
        # Read back rather than trusting the 200: Twilio accepts writes that do
        # not take effect, so confirm the trunk actually went back.
        # Equal, or both absent. The earlier form allowed "both non-blank",
        # which is true for every mismatch: a number restored to the wrong
        # trunk compared blank?("TKcomcent") == blank?("TKtheirs") and passed,
        # reporting a failed restore as a success -- the precise case this
        # read-back exists to catch.
        if updated["trunk_sid"] == original["trunk_sid"] or
             (blank?(updated["trunk_sid"]) and blank?(original["trunk_sid"])) do
          %{e164: provider_number.e164, ok: true}
        else
          %{
            e164: provider_number.e164,
            ok: false,
            error:
              "trunk is #{inspect(updated["trunk_sid"])}, expected #{inspect(original["trunk_sid"])}"
          }
        end

      {:error, {:not_found, _}} ->
        # Released in Twilio since we imported it. Nothing to restore.
        %{e164: provider_number.e164, ok: true, note: "no longer exists in the provider account"}

      {:error, reason} ->
        Logger.warning("Could not restore #{provider_number.e164}: #{inspect(reason)}")
        %{e164: provider_number.e164, ok: false, error: inspect(reason)}
    end
  end

  defp restore_number(_auth, provider_number) do
    %{
      e164: provider_number.e164,
      ok: false,
      error: "no original configuration was recorded, so it cannot be restored automatically"
    }
  end

  # Only the fields Comcent may have overwritten. TrunkSid must be sent even
  # when empty, since that is how the association is cleared.
  defp restore_params(original) do
    [
      {"TrunkSid", original["trunk_sid"] || ""},
      {"VoiceUrl", original["voice_url"]},
      {"VoiceMethod", original["voice_method"]},
      {"VoiceFallbackUrl", original["voice_fallback_url"]},
      {"VoiceApplicationSid", original["voice_application_sid"]},
      {"SmsUrl", original["sms_url"]},
      {"SmsMethod", original["sms_method"]},
      {"SmsFallbackUrl", original["sms_fallback_url"]},
      {"StatusCallback", original["status_callback"]}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Removes both the trunk and the credential list created alongside it. Neither
  # failure is fatal: an orphan is untidy, and blocking the disconnect over one
  # would trap the customer in the connection they are leaving.
  defp teardown_provider_trunk(connection) do
    auth = ProviderConnections.auth_for(connection)
    metadata = connection.metadata || %{}

    case metadata["trunk_sid"] do
      nil ->
        :ok

      trunk_sid ->
        case Twilio.delete_trunk(auth, trunk_sid) do
          :ok ->
            Logger.info("Deleted provider trunk #{trunk_sid}")

          {:error, reason} ->
            Logger.warning("Could not delete trunk #{trunk_sid}: #{inspect(reason)}")
        end
    end

    case metadata["credential_list_sid"] do
      nil ->
        :ok

      list_sid ->
        case Twilio.delete_credential_list(auth, list_sid) do
          :ok ->
            Logger.info("Deleted credential list #{list_sid}")
            :ok

          {:error, reason} ->
            Logger.warning("Could not delete credential list #{list_sid}: #{inspect(reason)}")
            :ok
        end
    end
  end

  # --- Comcent side --------------------------------------------------------

  defp remove_comcent_rows(connection, provider_numbers) do
    ids = Enum.map(provider_numbers, & &1.id)

    number_ids =
      from(n in Number, where: n.provider_number_id in ^ids, select: n.id) |> Repo.all()

    Repo.delete_all(from(c in NumberChannel, where: c.number_id in ^number_ids))
    Repo.delete_all(from(n in Number, where: n.id in ^number_ids))
    Repo.delete_all(from(p in ProviderNumber, where: p.id in ^ids))

    # Found by ownership rather than by a reconstructed name, which was fragile
    # if the label changed and could match a trunk the customer made themselves.
    from(st in SipTrunk, where: st.provider_connection_id == ^connection.id)
    |> Repo.all()
    |> Enum.each(fn trunk ->
      if Repo.aggregate(from(n in Number, where: n.sip_trunk_id == ^trunk.id), :count) == 0 do
        Repo.delete(trunk)
      end
    end)

    Repo.delete(connection)
  end

  # "Stop managing this account": we give up the API credentials and stop
  # touching the provider, but leave every provider-side resource exactly as it
  # is. Calls keep flowing -- the trunk authenticates by SIP credentials and IP,
  # not by the API key, so handing the key back costs the customer no service.
  #
  # The row is deliberately kept. It is the only place `trunk_sid` and
  # `credential_list_sid` are recorded, and the provider_numbers hanging off it
  # (ON DELETE CASCADE) hold each number's `original_config` -- the snapshot
  # that lets us put the numbers back later. Deleting the row would strand real
  # Twilio resources that nobody could identify afterwards, and would make
  # "stop managing" more destructive than a full release.
  defp deactivate(connection, _provider_numbers) do
    # The channels are deliberately left alone. Calls still flow in this mode,
    # so "voice: active" remains true -- it is the connection that is no longer
    # managed, and its own status says so. An earlier version wrote a status
    # onto number_channels that is not in NumberChannel's allowed list, which
    # `update_all` let through and which would have failed validation on every
    # later changeset touching those rows.
    connection
    |> ProviderConnection.changeset(%{"status" => "unmanaged", "credentials" => nil})
    |> Repo.update()
  end

  defp has_flow?(%Number{inbound_flow_graph: graph}) when is_map(graph) do
    map_size(Map.get(graph, "nodes", %{})) > 0
  end

  defp has_flow?(_), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
