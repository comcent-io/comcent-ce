defmodule ComcentWeb.ControllerJson do
  @moduledoc false

  def json(conn, data) do
    Phoenix.Controller.json(
      conn,
      data |> normalize_for_json() |> ComcentWeb.JsonCase.camel_case_keys()
    )
  end

  defp normalize_for_json(data) do
    data
    |> Jason.encode_to_iodata!()
    |> IO.iodata_to_binary()
    |> Jason.decode!()
  end
end
