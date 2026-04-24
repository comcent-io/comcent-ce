defmodule ComcentWeb.QueueDashboardChannel do
  use Phoenix.Channel
  require Logger

  alias Phoenix.PubSub

  def join("queue_dashboard:" <> data, _message, socket) do
    [subdomain, queue_id] = String.split(data, ":")

    if subdomain == socket.assigns.subdomain do
      # Subscribe this channel process to the scheduler's broadcasts for
      # this queue. Without this the `handle_info` below would never fire
      # — the socket assigns weren't enough on their own.
      PubSub.subscribe(Comcent.PubSub, "queue_dashboard:#{subdomain}:#{queue_id}")
      {:ok, assign(socket, :queue_id, queue_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info({:queue_dashboard_update, payload}, socket)
      when is_map(payload) do
    if payload[:queue_id] == socket.assigns.queue_id do
      push(socket, "queue_dashboard_update", ComcentWeb.JsonCase.camel_case_keys(payload))
    end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
