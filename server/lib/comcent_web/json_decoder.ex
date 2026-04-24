defmodule ComcentWeb.JsonDecoder do
  @moduledoc false

  def decode!(body) do
    decode!(body, [])
  end

  def decode!(body, opts) do
    body
    |> Jason.decode!(opts)
    |> ComcentWeb.JsonCase.snake_case_keys()
  end
end
