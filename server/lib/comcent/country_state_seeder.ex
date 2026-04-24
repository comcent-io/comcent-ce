defmodule Comcent.CountryStateSeeder do
  @moduledoc false

  require Logger

  alias Comcent.Repo
  alias Comcent.Schemas.{Country, State}

  def seed_if_needed do
    country_count = Repo.aggregate(Country, :count, :id)
    state_count = Repo.aggregate(State, :count, :id)

    if country_count == 0 or state_count == 0 do
      Logger.info("Seeding countries and states")
      do_seed()
    else
      :ok
    end
  end

  defp do_seed do
    countries = load_country_data()

    Repo.transaction(fn ->
      if Repo.aggregate(Country, :count, :id) == 0 do
        Repo.insert_all(Country, build_country_rows(countries))
      end

      if Repo.aggregate(State, :count, :id) == 0 do
        Repo.insert_all(State, build_state_rows(countries))
      end
    end)

    :ok
  rescue
    error ->
      Logger.error("Failed to seed countries and states: #{Exception.message(error)}")
      :error
  end

  defp load_country_data do
    :comcent
    |> :code.priv_dir()
    |> Path.join("country_states.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp build_country_rows(countries) do
    Enum.map(countries, fn %{"code2" => code, "name" => name} ->
      %{code: code, name: name}
    end)
  end

  defp build_state_rows(countries) do
    countries
    |> Enum.flat_map(fn %{"code2" => country_code, "states" => states} ->
      Enum.map(states, fn %{"name" => name} ->
        %{name: name, country_code: country_code}
      end)
    end)
  end
end
