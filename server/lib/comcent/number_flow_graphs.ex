defmodule Comcent.NumberFlowGraphs do
  alias Comcent.Repo.Number

  def get_number_flow_graphs(subdomain) do
    Number.get_numbers_by_org(subdomain)
    |> Enum.filter(fn number -> number.inbound_flow_graph != nil end)
    |> Enum.map(fn number ->
      %{
        number: number.number,
        flow_graph: number.inbound_flow_graph
      }
    end)
  end
end
