defmodule Comcent.Types.Json do
  use Ecto.Type

  def type, do: :map

  def cast(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end

  def cast(value) when is_list(value), do: {:ok, value}
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end

  def load(value) when is_list(value), do: {:ok, value}
  def load(value) when is_map(value), do: {:ok, value}
  def load(nil), do: {:ok, nil}
  def load(_), do: :error

  def dump(value) when is_list(value), do: {:ok, value}
  def dump(value) when is_map(value), do: {:ok, value}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error
end
