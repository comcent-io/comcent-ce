defmodule Comcent.Repo do
  use Ecto.Repo,
    otp_app: :comcent,
    adapter: Ecto.Adapters.Postgres
end
