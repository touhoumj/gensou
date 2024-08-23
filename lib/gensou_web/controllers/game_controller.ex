defmodule GensouWeb.GameController do
  use GensouWeb, :controller

  def socket(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(
      GensouWeb.GameSocket,
      %{remote_ip: remote_ip(conn), host: conn.host},
      timeout: :timer.minutes(1)
    )
    |> halt()
  end

  defp remote_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value
      _ -> :inet.ntoa(conn.remote_ip)
    end
  end
end
