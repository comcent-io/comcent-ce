defmodule ComcentWeb.VoiceBotController do
  use ComcentWeb, :controller
  require Logger

  alias Comcent.GetQueueIds
  alias Comcent.Repo
  alias Comcent.Repo.{VoiceBot, Org}
  alias Comcent.Schemas.VoiceBot, as: VoiceBotSchema

  def get_voice_bots(conn, _params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting voice bots for org #{subdomain}")
    voice_bots = VoiceBot.get_voicebots_by_org(subdomain)
    json(conn, %{voice_bots: voice_bots})
  end

  def get_voice_bot(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Getting voice bot #{id} for org #{subdomain}")

    case VoiceBot.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "VoiceBot not found"})

      voice_bot ->
        json(conn, voice_bot)
    end
  end

  def create(conn, params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Creating voice bot for org #{subdomain}")

    case Org.get_org_by_subdomain(subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Organization not found"})

      org ->
        api_key = :crypto.strong_rand_bytes(64) |> Base.encode16(case: :lower)

        attrs = %{
          "name" => params["name"],
          "instructions" => params["instructions"],
          "not_to_do_instructions" => params["not_to_do_instructions"],
          "greeting_instructions" => params["greeting_instructions"] || "",
          "mcp_servers" => params["mcp_servers"] || [],
          "is_hangup" => params["is_hangup"] || false,
          "is_enqueue" => params["is_enqueue"] || false,
          "queues" => params["queues"] || [],
          "pipeline" => params["pipeline"],
          "api_key" => api_key,
          "org_id" => org.id
        }

        new_voice_bot = %VoiceBotSchema{id: Ecto.UUID.generate()}

        case Repo.insert(VoiceBotSchema.changeset(new_voice_bot, attrs)) do
          {:ok, voice_bot} ->
            Logger.info("Voice bot created successfully for org #{subdomain}")
            conn |> put_status(:ok) |> json(voice_bot)

          {:error, changeset} ->
            Logger.error("Failed to create voice bot: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Updating voice bot #{id} for org #{subdomain}")

    case VoiceBot.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "VoiceBot not found"})

      voice_bot ->
        attrs =
          Map.take(params, [
            "name",
            "instructions",
            "not_to_do_instructions",
            "greeting_instructions",
            "mcp_servers",
            "is_hangup",
            "is_enqueue",
            "queues",
            "pipeline"
          ])

        case Repo.update(VoiceBotSchema.changeset(voice_bot, attrs)) do
          {:ok, updated} ->
            Logger.info("Voice bot #{id} updated successfully")
            conn |> put_status(:ok) |> json(updated)

          {:error, changeset} ->
            Logger.error("Failed to update voice bot: #{inspect(changeset.errors)}")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    subdomain = conn.assigns[:subdomain]
    Logger.info("Deleting voice bot #{id} for org #{subdomain}")

    case VoiceBot.get_by_id(id, subdomain) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "VoiceBot not found"})

      voice_bot ->
        voice_bot_number_map = GetQueueIds.get_number_map_for_voicebot_ids(subdomain)

        case Map.get(voice_bot_number_map, voice_bot.id) do
          numbers when is_list(numbers) and numbers != [] ->
            numbers_str = Enum.join(numbers, ", ")

            error_msg =
              "Cannot delete #{voice_bot.name} as it is used in inbound flow graph in numbers #{numbers_str}"

            Logger.error(error_msg)
            conn |> put_status(:conflict) |> json(%{error: error_msg})

          _ ->
            case Repo.delete(voice_bot) do
              {:ok, _} ->
                Logger.info("Voice bot #{id} deleted successfully")

                conn
                |> put_status(:ok)
                |> json(%{message: "VoiceBot with id #{id} deleted successfully"})

              {:error, changeset} ->
                Logger.error("Failed to delete voice bot: #{inspect(changeset.errors)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to delete voice bot"})
            end
        end
    end
  end

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
