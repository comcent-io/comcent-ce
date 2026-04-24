defmodule ComcentWeb.Internal.VoiceBotController do
  use ComcentWeb, :controller

  def get_voice_bot(conn, %{"id" => id}) do
    voice_bot = Comcent.VoiceBot.get_voice_bot(id)

    conn
    |> put_status(:ok)
    |> json(voice_bot)
  end
end
