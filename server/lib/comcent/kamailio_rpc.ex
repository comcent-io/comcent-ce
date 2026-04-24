defmodule Comcent.KamailioRPC do
  @moduledoc """
  Module for handling Kamailio RPC operations.
  """

  require Logger

  @doc """
  Sends an RPC request to remove an IP address from the dispatcher.
  """
  def send_rpc_request_to_remove_ip_address(ip_address) do
    {url, api_token} = get_rpc_config()

    rpc_data = %{
      jsonrpc: "2.0",
      method: "dispatcher.remove",
      params: [2, "sip:#{ip_address}:5070"],
      id: 1
    }

    headers = [{"X-Api-Token", api_token}]

    case Jason.encode(rpc_data) do
      {:ok, encoded_data} ->
        case HTTPoison.post(url, encoded_data, headers) do
          {:ok, response} ->
            case Jason.decode(response.body) do
              {:ok, _decoded} ->
                Logger.info("RPC request sent successfully")
                :ok

              {:error, _} ->
                {:error, :invalid_json_response}
            end

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Checks if an IP address exists in the dispatcher list.
  """
  def is_ip_address_in_dispatcher(ip_address) do
    {url, api_token} = get_rpc_config()

    rpc_data = %{
      jsonrpc: "2.0",
      method: "dispatcher.list",
      id: 1
    }

    headers = [{"X-Api-Token", api_token}]

    case Jason.encode(rpc_data) do
      {:ok, encoded_data} ->
        case HTTPoison.post(url, encoded_data, headers) do
          {:ok, response} ->
            case Jason.decode(response.body) do
              {:ok, %{"result" => %{"RECORDS" => records}}} ->
                uri_exists =
                  Enum.any?(records, fn record ->
                    case record do
                      %{"SET" => %{"TARGETS" => targets}} ->
                        Enum.any?(targets, fn target ->
                          case target do
                            %{"DEST" => %{"URI" => uri}} -> uri == "sip:#{ip_address}:5070"
                            _ -> false
                          end
                        end)

                      _ ->
                        false
                    end
                  end)

                uri_exists

              _ ->
                false
            end

          {:error, %{status_code: 404}} ->
            false

          {:error, error} ->
            Logger.error(
              "Error in sending RPC request to check IP address in dispatcher list: #{inspect(error)}"
            )

            false
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Sends an RPC request to add an IP address to the dispatcher.
  """
  def send_rpc_request_to_add_ip_address(ip_address) do
    {url, api_token} = get_rpc_config()

    rpc_data = %{
      jsonrpc: "2.0",
      method: "dispatcher.add",
      params: [2, "sip:#{ip_address}:5070"],
      id: 1
    }

    headers = [{"X-Api-Token", api_token}]

    case Jason.encode(rpc_data) do
      {:ok, encoded_data} ->
        case HTTPoison.post(url, encoded_data, headers) do
          {:ok, response} ->
            case Jason.decode(response.body) do
              {:ok, _decoded} ->
                Logger.info("RPC request sent successfully")
                :ok

              {:error, _} ->
                {:error, :invalid_json_response}
            end

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # Private function to get RPC configuration
  defp get_rpc_config do
    config = Application.get_env(:comcent, :kamailio)
    url = "http://#{config[:ip]}/rpc"
    api_token = config[:rpc_api_token]
    {url, api_token}
  end
end
