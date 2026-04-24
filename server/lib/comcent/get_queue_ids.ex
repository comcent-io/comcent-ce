defmodule Comcent.GetQueueIds do
  alias Comcent.NumberFlowGraphs
  alias Comcent.Repo.VoiceBot

  def get_queue_ids_from_number_flow_graphs(subdomain) do
    NumberFlowGraphs.get_number_flow_graphs(subdomain)
    |> Enum.reduce(%{}, fn number_flow_graph, acc ->
      number_flow_graph.flow_graph
      |> graph_nodes()
      |> Enum.filter(fn node -> node["type"] == "Queue" end)
      |> Enum.reduce(acc, fn node, queue_acc ->
        queue_id = node["data"]["queue"]

        Map.update(
          queue_acc,
          queue_id,
          [number_flow_graph.number],
          &[number_flow_graph.number | &1]
        )
      end)
    end)
  end

  def get_voicebots_with_queue(subdomain, queue_name) do
    VoiceBot.get_voicebots_by_org(subdomain)
    |> Enum.filter(fn voicebot ->
      length(voicebot.queues) > 0 && Enum.member?(voicebot.queues, queue_name)
    end)
    |> Enum.map(fn voicebot -> voicebot.name end)
  end

  def get_number_map_for_voicebot_ids(subdomain) do
    NumberFlowGraphs.get_number_flow_graphs(subdomain)
    |> Enum.reduce(%{}, fn number_flow_graph, acc ->
      number_flow_graph.flow_graph
      |> graph_nodes()
      |> Enum.filter(fn node -> node["type"] == "VoiceBot" end)
      |> Enum.reduce(acc, fn node, voicebot_acc ->
        voice_bot_id = node["data"]["voiceBotId"] || node["data"]["voice_bot_id"]

        if is_binary(voice_bot_id) and voice_bot_id != "" do
          Map.update(
            voicebot_acc,
            voice_bot_id,
            [number_flow_graph.number],
            &[number_flow_graph.number | &1]
          )
        else
          voicebot_acc
        end
      end)
    end)
  end

  defp graph_nodes(%{"nodes" => nodes}) when is_map(nodes), do: Map.values(nodes)
  defp graph_nodes(%{nodes: nodes}) when is_map(nodes), do: Map.values(nodes)
  defp graph_nodes(_), do: []
end
