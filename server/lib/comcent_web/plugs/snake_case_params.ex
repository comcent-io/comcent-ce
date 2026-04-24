defmodule ComcentWeb.Plugs.SnakeCaseParams do
  @moduledoc false

  def init(opts), do: opts

  def call(conn, _opts) do
    converted_body_params = merge_preserving_original(conn.body_params)
    converted_query_params = merge_preserving_original(conn.query_params)
    converted_path_params = merge_preserving_original(conn.path_params)

    converted_params =
      conn.params
      |> Map.merge(converted_query_params)
      |> Map.merge(converted_body_params)
      |> Map.merge(converted_path_params)

    %{
      conn
      | body_params: converted_body_params,
        query_params: converted_query_params,
        path_params: converted_path_params,
        params: converted_params
    }
  end

  defp merge_preserving_original(params) when is_map(params) do
    snake_case_params = ComcentWeb.JsonCase.snake_case_keys(params)
    Map.merge(params, snake_case_params)
  end

  defp merge_preserving_original(params), do: params
end
