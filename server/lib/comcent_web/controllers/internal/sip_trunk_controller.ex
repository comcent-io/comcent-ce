defmodule ComcentWeb.Internal.SipTrunkController do
  use ComcentWeb, :controller
  require Logger
  import Ecto.Query
  alias Comcent.Repo

  def create(conn, params) do
    Logger.info("Received POST request to /internal/number/sip-trunk")
    Logger.info("params: #{inspect(params)}")

    %{"number" => number} = params

    query =
      from(n in "numbers",
        join: s in "sip_trunks",
        on: n.sip_trunk_id == s.id,
        where: n.number == ^number,
        select: %{
          number: n.number,
          outbound_username: s.outbound_username,
          outbound_password: s.outbound_password,
          outbound_contact: s.outbound_contact,
          inbound_ips: s.inbound_ips
        }
      )

    case Repo.one(query) do
      nil ->
        conn
        |> put_status(404)
        |> text("Number not found")

      sip_number ->
        conn
        |> put_status(:ok)
        |> json(%{
          outbound_username: sip_number.outbound_username,
          outbound_password: sip_number.outbound_password,
          outbound_contact: sip_number.outbound_contact,
          inbound_ips: sip_number.inbound_ips
        })
    end
  end
end
