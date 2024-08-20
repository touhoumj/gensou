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
  def update_room(room), do: GenServer.cast(__MODULE__, {:update_room, room})
  def remove_room(room), do: GenServer.cast(__MODULE__, {:remove_room, room})
end
