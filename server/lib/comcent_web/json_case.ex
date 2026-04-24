defmodule ComcentWeb.JsonCase do
  @moduledoc false

  def snake_case_keys(data) do
    convert_keys(data, &Recase.to_snake/1)
  end

  def camel_case_keys(data) do
    convert_keys(data, &Recase.to_camel/1)
  end

  defp convert_keys(data, convert_fun) when is_map(data) do
    if is_struct(data) do
      data
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> convert_keys(convert_fun)
    else
      data
      |> Enum.map(fn {key, value} ->
        {convert_key(key, convert_fun), convert_keys(value, convert_fun)}
      end)
      |> Enum.into(%{})
    end
  end

  defp convert_keys(data, convert_fun) when is_list(data) do
    Enum.map(data, &convert_keys(&1, convert_fun))
  end

  defp convert_keys(data, _convert_fun), do: data

  defp convert_key(key, convert_fun) when is_atom(key) do
    key
    |> Atom.to_string()
    |> convert_fun.()
    |> String.to_atom()
  end

  defp convert_key(key, convert_fun) when is_binary(key) do
    if String.match?(key, ~r/[a-z_]/) do
      convert_fun.(key)
    else
      key
    end
  end

  defp convert_key(key, _convert_fun), do: key
end
