defmodule Comcent.Call.Persistence do
  @moduledoc """
  DB writes for a completed call story. Called from `Comcent.Call` when the
  call lifecycle has ended (all channels closed and all recordings uploaded).
  """

  require Logger

  alias Comcent.Repo
  alias Comcent.Schemas.{CallSpan, CallStory, CallStoryEvent, Number, Org}

  @type span :: map()
  @type event :: map()

  @spec save(map(), [span()], [event()]) :: {:ok, CallStory.t()} | {:error, term()}
  def save(call_story_record, spans, events \\ []) do
    subdomain = get_subdomain_from_story(call_story_record)

    case subdomain && get_org_id_from_subdomain(subdomain) do
      nil ->
        Logger.error(
          "Could not determine org for call story #{inspect(call_story_record)}; skipping persistence"
        )

        {:error, :unknown_org}

      org_id ->
        attrs = %{
          id: Map.get(call_story_record, :id),
          caller: Map.get(call_story_record, :caller),
          callee: Map.get(call_story_record, :callee),
          direction: Map.get(call_story_record, :direction),
          outbound_caller_id: Map.get(call_story_record, :outbound_caller_id),
          hangup_party: Map.get(call_story_record, :hangup_party),
          start_at: Map.get(call_story_record, :start_at),
          end_at: DateTime.utc_now(),
          org_id: org_id
        }

        Repo.transaction(fn ->
          with {:ok, saved} <- Repo.insert(CallStory.changeset(%CallStory{}, attrs)),
               :ok <- insert_spans(spans),
               :ok <- insert_events(events) do
            saved
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, saved} ->
            Logger.info("Successfully saved call story with ID: #{saved.id}")
            {:ok, saved}

          {:error, reason} = err ->
            Logger.error("Failed to save call story #{attrs.id}: #{inspect(reason)}")

            err
        end
    end
  end

  def get_subdomain_from_story(call_story) when is_map(call_story) do
    sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

    cond do
      Map.has_key?(call_story, :current_party) and
          string_contains?(call_story.current_party, sip_user_root_domain) ->
        extract_subdomain(call_story.current_party)

      Map.has_key?(call_story, :caller) and
          string_contains?(call_story.caller, sip_user_root_domain) ->
        extract_subdomain(call_story.caller)

      Map.has_key?(call_story, :callee) and call_story.callee != nil ->
        case Repo.get_by(Number, number: call_story.callee) |> maybe_preload() do
          nil -> nil
          number -> number.org && number.org.subdomain
        end

      true ->
        Logger.error("Could not determine subdomain from call story: #{inspect(call_story)}")
        nil
    end
  end

  def get_subdomain_from_story(_), do: nil

  defp maybe_preload(nil), do: nil
  defp maybe_preload(number), do: Repo.preload(number, :org)

  defp string_contains?(nil, _), do: false
  defp string_contains?(str, substr) when is_binary(str), do: String.contains?(str, substr)
  defp string_contains?(_, _), do: false

  defp extract_subdomain(party) do
    case String.split(party, "@") do
      [_, domain] ->
        domain |> String.split(".") |> List.first()

      _ ->
        nil
    end
  end

  defp get_org_id_from_subdomain(nil), do: nil

  defp get_org_id_from_subdomain(subdomain) do
    case Repo.get_by(Org, subdomain: subdomain) do
      nil -> nil
      org -> org.id
    end
  end

  defp insert_spans(spans) do
    Enum.reduce_while(spans, :ok, fn span, :ok ->
      span = Map.put(span, :id, Ecto.UUID.generate())

      case Repo.insert(CallSpan.changeset(%CallSpan{}, span)) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_events(events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      event = Map.put(event, :id, Ecto.UUID.generate())

      case Repo.insert(CallStoryEvent.changeset(%CallStoryEvent{}, event)) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
