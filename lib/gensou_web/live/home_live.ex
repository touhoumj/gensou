defmodule GensouWeb.HomeLive do
  use GensouWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, lobby} = Gensou.Lobby.get_info()

    if connected?(socket) do
      Gensou.Lobby.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:game_socket_uri, game_socket_uri())
     |> assign(:lobby, lobby)}
  end

  @impl true
  def handle_info({:lobby_changed, lobby}, socket) do
    {:noreply, assign(socket, :lobby, lobby)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp game_socket_uri() do
    String.replace_leading(url(~p"/game_socket"), "http", "ws")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article id="content" class="prose prose-a:text-blue-700 max-w-none">
      <h3>This is an instance of Gensou - a Touhou Unreal Mahjong 4N server.</h3>
      <p>
        You can connect to it by configuring the server address in your game to: <pre><%= @game_socket_uri %></pre>
      </p>
      <p>
        Make sure to check out the
        <a href="https://github.com/touhoumj/gensou-client" target="_blank">
          Gensou client repository
        </a>
        for more detailed instructions.
      </p>
      <h3 class="-mb-6">Lobby</h3>
      <.table id="lobby" rows={@lobby.rooms}>
        <:col :let={room} label="id"><%= room.id %></:col>
        <:col :let={room} label="name"><%= room.name %></:col>
        <:col :let={room} label="players"><%= room.player_count %></:col>
        <:col :let={room} label="status"><%= room.status %></:col>
      </.table>
    </article>
    """
  end
end
