defmodule GensouWeb.GameController do
  use GensouWeb, :controller

  def socket(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(
      GensouWeb.GameSocket,
      %{remote_ip: conn.remote_ip, port: conn.port},
      timeout: :timer.minutes(10)
    )
    |> halt()
  end
end
