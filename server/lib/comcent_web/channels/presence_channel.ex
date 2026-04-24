defmodule ComcentWeb.PresenceChannel do
  use Phoenix.Channel
  require Logger

  def join("presence:" <> subdomain, _message, socket) do
    if subdomain == socket.assigns.subdomain do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle messages from PubSub broadcast
  def handle_info(
        {:presence_update,
         %{user_id: user_id, presence: presence, previous_presence: previous_presence}},
        socket
      ) do
    subdomain = socket.assigns.subdomain
    Logger.info("Handling presence update for user #{user_id}: #{presence} in #{subdomain}")

    # Push the message to the client. Keys are camelCased to match the
    # client-side handler (payload.userId, payload.previousPresence).
    push(socket, "presence_update", %{
      userId: user_id,
      presence: presence,
      previousPresence: previous_presence
    })

    {:noreply, socket}
  end
end
