defmodule Comcent.Provisioning do
  @moduledoc """
  Turns an imported provider number into a number Comcent can route.

  Twilio Elastic SIP Trunking maps one-to-one onto primitives Comcent already
  has, so this writes ordinary `sip_trunks` and `numbers` rows and the SBC picks
  them up unchanged — no changes to the Go SBC or FreeSWITCH:

      Twilio termination URI  <x>.pstn.twilio.com  ->  sip_trunks.outbound_contact
      Twilio credential list entry                 ->  outbound_username/password
      Twilio origination URI  sip:<our sbc>        ->  (Twilio side)
      Twilio signaling CIDRs                       ->  sip_trunks.inbound_ips

  ## A 2xx from Twilio is not proof

  Every write here is followed by a read-back, because three operations in this
  flow return success while doing nothing useful (all three verified against a
  live account):

    * `POST /Trunks` without `DomainName` returns 201 with `domain_name: null` —
      a trunk with no termination URI, which can never route
    * associating a number already on another trunk returns 201 and silently
      steals it
    * setting `sms_url` on a number in a Messaging Service returns 200 and is
      ignored

  So the read-back result, not the HTTP status, is what marks a step done.
  """

  require Logger

  import Ecto.Query

  alias Comcent.Repo
  alias Comcent.ProviderConnections
  alias Comcent.Schemas.{Number, NumberChannel, ProviderConnection, ProviderNumber, SipTrunk}
  alias Comcent.Twilio

  # Twilio rejects a duplicate trunk domain with 21248. These are DNS names
  # under pstn.twilio.com, so uniqueness is global rather than per-account and a
  # collision with an unrelated Twilio customer is possible.
  @domain_collision_code 21248
  @domain_attempts 5

  @doc """
  Provisions one imported number end to end.

  Reuses the connection's trunk if it already has one, so importing a second
  number does not create a second trunk.
  """
  def provision(
        %ProviderConnection{} = connection,
        %ProviderNumber{} = provider_number,
        opts \\ []
      ) do
    # Reloaded rather than trusted: provisioning records the trunk on the
    # connection, so a caller holding a struct from before the first import
    # would look like a connection with no trunk and get a second one built.
    connection = Repo.get(ProviderConnection, connection.id) || connection
    auth = ProviderConnections.auth_for(connection)

    with {:ok, sbc_fqdn} <- sbc_fqdn(),
         {:ok, trunk} <- ensure_trunk(auth, connection, sbc_fqdn),
         {:ok, sip_trunk} <- ensure_sip_trunk_row(connection, trunk),
         :ok <- attach_number(auth, trunk.sid, provider_number),
         {:ok, number} <- create_number_row(connection, provider_number, sip_trunk, opts),
         {:ok, _channel} <- create_voice_channel(connection, number, trunk),
         {:ok, _} <- record_expected_trunk(provider_number, trunk) do
      {:ok, %{number: number, sip_trunk: sip_trunk, trunk_sid: trunk.sid}}
    end
  end

  @doc """
  Imports a number and provisions it, rolling the import back if provisioning
  fails.

  These are separate steps but not independently useful: an imported number
  that never got a trunk is one we claim to own with no way for calls to reach
  it. Leaving the row behind would also make a retry trip over its own
  half-finished attempt, so the import is undone on failure.
  """
  def import_and_provision(%ProviderConnection{} = connection, provider_sid, opts \\ []) do
    alias Comcent.ProviderNumbers

    case ProviderNumbers.import_number(connection, provider_sid, opts) do
      {:ok, provider_number} ->
        case provision(connection, provider_number, opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            Logger.warning(
              "Provisioning #{provider_number.e164} failed (#{inspect(reason)}); rolling back the import"
            )

            # Restore before deleting. Provisioning may already have moved the
            # number onto the Comcent trunk, and the row being deleted holds
            # the only snapshot of how it was configured beforehand -- dropping
            # it would strand the number on a trunk with no way back.
            Comcent.ProviderDisconnect.release_number(provider_number)
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  # --- trunk ---------------------------------------------------------------

  # One trunk per connection. Recorded on the connection so a second import
  # reuses it instead of creating another.
  defp ensure_trunk(auth, connection, sbc_fqdn) do
    case get_in(connection.metadata || %{}, ["trunk_sid"]) do
      nil ->
        create_trunk(auth, connection, sbc_fqdn)

      trunk_sid ->
        case Twilio.get_trunk(auth, trunk_sid) do
          {:ok, trunk} ->
            {:ok, normalise_trunk(trunk)}

          {:error, {:not_found, _}} ->
            # Deleted in Twilio behind our back. Build a fresh one rather than
            # failing every future import.
            Logger.warning("Trunk #{trunk_sid} missing in Twilio; creating a replacement")
            create_trunk(auth, connection, sbc_fqdn)

          {:error, _} = error ->
            error
        end
    end
  end

  defp create_trunk(auth, connection, sbc_fqdn, attempt \\ 1) do
    friendly = "comcent-#{connection.id}"
    domain = trunk_domain(connection)

    case Twilio.create_trunk(auth, friendly, domain) do
      {:ok, trunk} ->
        # Until remember_trunk runs, nothing in Comcent knows this trunk
        # exists. If a later step fails we have to delete it here or it is
        # orphaned in the customer's account forever -- unidentifiable, and one
        # more added by every retry.
        with :ok <- assert_domain_present(trunk),
             :ok <- add_origination(auth, trunk["sid"], sbc_fqdn),
             {:ok, creds} <- add_termination_credentials(auth, trunk["sid"], connection),
             {:ok, remembered} <-
               remember_trunk(connection, trunk["sid"], creds.credential_list_sid) do
          _ = remembered
          {:ok, normalise_trunk(trunk, creds)}
        else
          {:error, reason} ->
            discard_trunk(auth, trunk["sid"])
            {:error, reason}
        end

      {:error, {:twilio_error, @domain_collision_code, _}} when attempt < @domain_attempts ->
        # Globally unique namespace, so a collision is expected occasionally.
        # Regenerate rather than surfacing an error the customer cannot act on.
        Logger.info("Trunk domain collision, retrying (attempt #{attempt + 1})")
        create_trunk(auth, connection, sbc_fqdn, attempt + 1)

      {:error, _} = error ->
        error
    end
  end

  # domain_name is optional to Twilio but required in practice: omit it and the
  # trunk comes back with no termination URI and can never route.
  defp assert_domain_present(%{"domain_name" => domain}) when is_binary(domain) and domain != "",
    do: :ok

  defp assert_domain_present(trunk) do
    {:error,
     {:provisioning_failed,
      "Trunk #{trunk["sid"]} was created without a termination domain, so nothing can route through it."}}
  end

  defp trunk_domain(connection) do
    # Trim after slicing, not before: slicing a trimmed string can put the
    # hyphen straight back on the end. A label with no alphanumerics at all
    # ("!!!") trims to nothing and would yield a domain starting with a hyphen,
    # which Twilio rejects with a code the retry does not handle -- so fall
    # back rather than emit an invalid label.
    slug =
      (connection.label || "comcent")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.slice(0, 20)
      |> String.trim("-")
      |> case do
        "" -> "comcent"
        trimmed -> trimmed
      end

    suffix =
      :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()

    suffix = String.replace(suffix, ~r/[^a-z0-9]/, "")

    "#{slug}-#{suffix}.pstn.twilio.com"
  end

  defp add_origination(auth, trunk_sid, sbc_fqdn) do
    case Twilio.create_origination_url(auth, trunk_sid,
           friendly_name: "comcent-sbc",
           sip_url: "sip:#{sbc_fqdn}"
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp add_termination_credentials(auth, trunk_sid, connection) do
    username = "comcent_" <> random_token(12)
    password = random_token(32)

    # Name includes a random suffix: Twilio rejects duplicates with 21240, and a
    # retry after a partial failure would otherwise collide with its own leftover.
    list_name = "comcent-#{String.slice(connection.id, 0, 8)}-#{random_token(6)}"

    with {:ok, list} <- Twilio.create_credential_list(auth, list_name),
         {:ok, _} <- Twilio.create_credential(auth, list["sid"], username, password),
         {:ok, _} <- Twilio.attach_credential_list(auth, trunk_sid, list["sid"]) do
      {:ok, %{username: username, password: password, credential_list_sid: list["sid"]}}
    end
  end

  # Both SIDs are recorded because disconnect has to remove both. A credential
  # list left behind is invisible until someone notices their Twilio account
  # accumulating one per connect/disconnect cycle.
  defp remember_trunk(connection, trunk_sid, credential_list_sid) do
    connection
    |> ProviderConnection.changeset(%{
      "metadata" =>
        Map.merge(connection.metadata || %{}, %{
          "trunk_sid" => trunk_sid,
          "credential_list_sid" => credential_list_sid
        })
    })
    |> Repo.update()
  end

  defp normalise_trunk(trunk, creds \\ nil) do
    %{
      sid: trunk["sid"],
      domain_name: trunk["domain_name"],
      credentials: creds
    }
  end

  # --- number --------------------------------------------------------------

  defp attach_number(auth, trunk_sid, provider_number) do
    with {:ok, _} <- Twilio.associate_phone_number(auth, trunk_sid, provider_number.provider_sid),
         {:ok, number} <- Twilio.get_incoming_phone_number(auth, provider_number.provider_sid) do
      # Read-back: the association returns 201 even when it does something other
      # than what we asked, so confirm the number really landed on our trunk.
      if number["trunk_sid"] == trunk_sid do
        :ok
      else
        {:error,
         {:provisioning_failed,
          "Twilio accepted the association but #{provider_number.e164} is on trunk " <>
            "#{inspect(number["trunk_sid"])} rather than #{trunk_sid}."}}
      end
    end
  end

  # --- Comcent rows --------------------------------------------------------

  defp ensure_sip_trunk_row(connection, trunk) do
    # Looked up by the connection that owns it, not by a name we constructed.
    # Name matching broke if the label changed and could collide with a trunk
    # the customer created themselves.
    case Repo.one(
           from(st in SipTrunk, where: st.provider_connection_id == ^connection.id, limit: 1)
         ) do
      %SipTrunk{} = existing ->
        # The trunk may have been rebuilt since this row was written -- if the
        # customer deleted ours in Twilio, ensure_trunk creates a replacement
        # with a new domain and new credentials. Leaving the row untouched
        # would keep every outbound call dialling the dead trunk while
        # provisioning still reported success.
        refresh_sip_trunk_row(existing, trunk)

      nil ->
        creds = trunk.credentials || %{}

        %SipTrunk{id: Ecto.UUID.generate()}
        |> SipTrunk.changeset(%{
          "name" => sip_trunk_name(connection),
          "outbound_contact" => trunk.domain_name,
          "outbound_username" => Map.get(creds, :username),
          "outbound_password" => Map.get(creds, :password),
          "inbound_ips" => signaling_cidrs(),
          "org_id" => connection.org_id,
          "provider_connection_id" => connection.id
        })
        |> Repo.insert()
    end
  end

  defp discard_trunk(auth, trunk_sid) do
    case Twilio.delete_trunk(auth, trunk_sid) do
      :ok ->
        Logger.info("Removed half-built trunk #{trunk_sid}")

      {:error, reason} ->
        # Reported, not raised: the original failure is the useful one, and an
        # orphan we told someone about beats swallowing the real error.
        Logger.error(
          "Left an orphaned trunk #{trunk_sid} in the provider account: #{inspect(reason)}"
        )
    end
  end

  defp refresh_sip_trunk_row(%SipTrunk{} = existing, trunk) do
    creds = trunk.credentials || %{}

    # Credentials are only present when the trunk was just created; reusing an
    # existing trunk returns none, and the stored ones are still correct.
    changes =
      %{"outbound_contact" => trunk.domain_name}
      |> maybe_put("outbound_username", Map.get(creds, :username))
      |> maybe_put("outbound_password", Map.get(creds, :password))

    if stale?(existing, changes) do
      Logger.info("SIP trunk #{existing.id} points at a replaced trunk; updating it")
      existing |> SipTrunk.changeset(changes) |> Repo.update()
    else
      {:ok, existing}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stale?(existing, changes) do
    Enum.any?(changes, fn {key, value} ->
      Map.get(existing, String.to_existing_atom(key)) != value
    end)
  end

  defp sip_trunk_name(connection) do
    ("Twilio " <> (connection.label || "connection")) |> String.slice(0, 25)
  end

  defp create_number_row(connection, provider_number, sip_trunk, opts) do
    %Number{id: Ecto.UUID.generate()}
    |> Number.changeset(%{
      "name" => provider_number.friendly_name || provider_number.e164,
      "number" => provider_number.e164,
      # Imported with no routing yet. The customer configures the flow in the
      # editor; an empty graph means "not routed" rather than a broken graph.
      "inbound_flow_graph" =>
        Keyword.get(opts, :inbound_flow_graph, %{"nodes" => %{}, "start" => nil}),
      "org_id" => connection.org_id,
      "sip_trunk_id" => sip_trunk.id,
      "provider_number_id" => provider_number.id
    })
    |> Repo.insert()
  end

  defp create_voice_channel(connection, number, trunk) do
    %NumberChannel{id: Ecto.UUID.generate()}
    |> NumberChannel.changeset(%{
      "org_id" => connection.org_id,
      "number_id" => number.id,
      "channel" => "voice",
      "status" => "active",
      "transport" => "sip_trunk",
      "config" => %{"trunk_sid" => trunk.sid, "termination_uri" => trunk.domain_name}
    })
    |> Repo.insert()
  end

  # Records which trunk Comcent put this number on. Drift detection compares
  # against this: without it there is no expected value, so nothing ever looks
  # changed and the check silently passes forever.
  defp record_expected_trunk(provider_number, trunk) do
    provider_number
    |> ProviderNumber.changeset(%{
      "provider_metadata" =>
        Map.merge(provider_number.provider_metadata || %{}, %{
          "comcent_trunk_sid" => trunk.sid
        })
    })
    |> Repo.update()
  end

  # --- config --------------------------------------------------------------

  # SBC_SIP_FQDN when it is set; otherwise the SBC's public IP, which a
  # self-hosted install already has, so connecting Twilio needs no new setting.
  defp sbc_fqdn do
    fqdn = Application.get_env(:comcent, :provisioning)[:sbc_sip_fqdn]
    public_ip = Application.get_env(:comcent, :sbc)[:public_ip]

    case Enum.find([fqdn, public_ip], &(&1 not in [nil, ""])) do
      nil ->
        {:error,
         {:configuration,
          "Neither SBC_SIP_FQDN nor SBC_PUBLIC_IP is set, so there is nowhere to point inbound calls."}}

      host ->
        {:ok, host}
    end
  end

  defp signaling_cidrs do
    Application.get_env(:comcent, :provisioning)[:twilio_signaling_cidrs] || []
  end

  defp random_token(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64(padding: false)
    |> String.replace(~r/[^A-Za-z0-9]/, "")
    |> String.slice(0, length)
  end
end
