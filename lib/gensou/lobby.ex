defmodule Gensou.Lobby do
  use GenServer

  def start_link(opts \\ []) do
    state = %{rooms: %{}}
    opts = Keyword.put(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:update_room, room}, state) do
    state = %{state | rooms: Map.put(state.rooms, room.id, room)}
    lobby = %Gensou.Model.Lobby{rooms: Map.values(state.rooms)}
    broadcast({:lobby_changed, lobby})
    {:noreply, state}
  end

  def handle_cast({:remove_room, room}, state) do
    state = %{state | rooms: Map.delete(state.rooms, room.id)}
    lobby = %Gensou.Model.Lobby{rooms: Map.values(state.rooms)}
    broadcast({:lobby_changed, lobby})
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    rooms = state.rooms |> Map.values() |> Enum.sort_by(& &1.id)
    lobby = %Gensou.Model.Lobby{rooms: rooms}
    {:reply, {:ok, lobby}, state}
  end

  def handle_call(:get_open_room, _from, state) do
    room =
      state.rooms
      |> Enum.filter(fn {_room_id, room} ->
        room.allow_quick_join and room.status == :waiting and
          room.player_count < Gensou.Model.Room.max_players(room)
      end)
      |> Enum.map(fn {_room_id, room} -> room end)
      |> Enum.take_random(1)
      |> Enum.at(0)

    if room do
      {:reply, {:ok, room}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def topic(), do: "lobby"

  def broadcast(event) do
    Phoenix.PubSub.broadcast(Gensou.PubSub, topic(), event)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Gensou.PubSub, topic())
  end

  def unsubscribe() do
    Phoenix.PubSub.unsubscribe(Gensou.PubSub, topic())
  end

  def get_info(), do: GenServer.call(__MODULE__, :get_info)
  def get_open_room(), do: GenServer.call(__MODULE__, :get_open_room)
  def update_room(room), do: GenServer.cast(__MODULE__, {:update_room, room})
  def remove_room(room), do: GenServer.cast(__MODULE__, {:remove_room, room})
end
