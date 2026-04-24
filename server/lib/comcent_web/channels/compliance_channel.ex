defmodule ComcentWeb.ComplianceChannel do
  use Phoenix.Channel
  require Logger

  def join("compliance:" <> subdomain, _message, socket) do
    if subdomain == socket.assigns.subdomain do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle messages from PubSub broadcast
  def handle_info(
        {:compliance_update, %{compliance_task_id: compliance_task_id, status: status}},
        socket
      ) do
    subdomain = socket.assigns.subdomain

    Logger.info(
      "Handling compliance status change of compliance #{compliance_task_id}: #{status} in #{subdomain}"
    )

    # Push the message to the client
    push(socket, "compliance_update", %{
      compliance_task_id: compliance_task_id,
      status: status
    })

    {:noreply, socket}
  end
end
