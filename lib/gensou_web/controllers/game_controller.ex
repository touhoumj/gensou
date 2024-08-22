defmodule GensouWeb.GameController do
  use GensouWeb, :controller

  def socket(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(
      GensouWeb.GameSocket,
      %{remote_ip: conn.remote_ip, host: conn.host, port: conn.port},
      timeout: :timer.minutes(1)
    )
    |> halt()
  end
end
