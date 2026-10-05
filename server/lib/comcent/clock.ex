defmodule Comcent.Clock do
  @moduledoc """
  The current time as the database stores it, and how operator emails and
  the admin panel write a timestamp. One place, instead of a private `now`
  in every module.
  """

  @doc "Now in UTC, to the second: what `:utc_datetime` fields hold."
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Now in UTC, to the second, without a zone: what `:naive_datetime` fields hold."
  def naive_now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  @doc """
  A timestamp for operator emails and the admin panel, "2026-09-29
  04:21:07 UTC". Given nil, `fallback`.
  """
  def format_utc(at, fallback \\ "an unknown time")
  def format_utc(nil, fallback), do: fallback
  def format_utc(at, _fallback), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")
end
