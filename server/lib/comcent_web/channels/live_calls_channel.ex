defmodule ComcentWeb.LiveCallsChannel do
  use Phoenix.Channel
  require Logger

  def join("live_calls:" <> subdomain, _message, socket) do
    if subdomain == socket.assigns.subdomain do
      socket = assign(socket, :subdomain, subdomain)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle messages from PubSub broadcast
  def handle_info(
        {:live_call_update,
         %{
           subdomain: subdomain,
           action: action,
           call_data: call_data
         }},
        socket
      ) do
    if subdomain != socket.assigns.subdomain do
      {:noreply, socket}
    end

    payload =
      %{
        action: action,
        call_data: call_data
      }
      |> normalize_for_json()
      |> ComcentWeb.JsonCase.camel_case_keys()

    # Push the message to the client
    push(socket, "live_call_update", payload)

    {:noreply, socket}
  end

  defp normalize_for_json(data) do
    data
    |> Jason.encode_to_iodata!()
    |> IO.iodata_to_binary()
    |> Jason.decode!()
  end
end
