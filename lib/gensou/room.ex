defmodule Gensou.Room do
  use GenServer, restart: :transient
  require Logger

  def start_link(opts \\ []) do
    settings = Keyword.fetch!(opts, :settings)

    room =
      Gensou.Model.Room.new!(%{
        id: System.os_time(:millisecond),
        name: settings.name,
        description: settings.description,
        time: settings.time,
        has_password: settings.has_password,
        table_name: settings.table_name,
        password: settings.password,
        enable_magic: settings.enable_magic,
        allow_quick_join: settings.allow_quick_join,
        game_length: settings.game_length,
        player_count: 0,
        status: :waiting
      })

    state = %{room: room, players: [], events: [], event_index: 1}
    opts = Keyword.put(opts, :name, address(room.id))
    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl GenServer
  def init(state) do
    Logger.info("[#{__MODULE__}] Created the room: #{inspect(state.room)}")
    schedule_room_gc()
    Gensou.Lobby.update_room(state.room)
    {:ok, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("[#{__MODULE__}] Removing the room: #{inspect(state.room)}")
    Gensou.Lobby.remove_room(state.room)
    reason
  end

  @impl GenServer
  def handle_info(:gc, state) do
    if has_active_human_players?(state) do
      {:noreply, state}
    else
      {:stop, :normal, state}
    end
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    {:reply, {:ok, state.room}, state}
  end

  def handle_call(:get_players, _from, state) do
    {:reply, {:ok, state.players}, state}
  end

  def handle_call({:get_player, player_id}, _from, state) do
    player = Enum.find(state.players, &(&1.id == player_id))

    if player do
      {:reply, {:ok, player}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:join, player, password}, _from, state) do
    # TODO prevent duplicate joins
    cond do
      state.room.has_password and state.room.password != password ->
        {:reply, {:error, :invalid_password}, state}

      Enum.count(state.players) >= Gensou.Model.Room.max_players(state.room) ->
        {:reply, {:error, :room_is_full}, state}

      true ->
        players = state.players ++ [player]
        room = Map.replace(state.room, :player_count, Enum.count(players))
        state = %{state | room: room, players: players}
        Gensou.Lobby.update_room(state.room)
        broadcast(state.room.id, {:player_joined, player})
        {:reply, {:ok, {state.room, state.players}}, state}
    end
  end

  def handle_call({:rejoin, player_id, last_event_index}, _from, state) do
    player_index = Enum.find_index(state.players, fn player -> player.id == player_id end)

    case player_index do
      nil ->
        {:reply, :error, :player_not_found}

      player_index ->
        players =
          List.update_at(
            state.players,
            player_index,
            &Map.replace(&1, :disconnected, false)
          )

        player = Enum.at(state.players, player_index)
        state = %{state | players: players}

        events =
          state.events
          # TODO confirm that this really should be inclusive
          |> Enum.filter(&(&1.index >= last_event_index))
          |> Enum.sort_by(& &1.index)

        broadcast(state.room.id, {:player_changed, :reconnected, player.id})
        {:reply, {:ok, {state.room, state.players, events}}, state}
    end
  end

  def handle_call({:add_cpu, player}, _from, state) do
    if Enum.count(state.players) < Gensou.Model.Room.max_players(state.room) do
      player = Map.replace(player, :ready, true)
      players = state.players ++ [player]
      room = Map.replace(state.room, :player_count, Enum.count(players))
      state = %{state | room: room, players: players}
      Gensou.Lobby.update_room(state.room)
      broadcast(state.room.id, {:player_joined, player})
      {:reply, {:ok, {state.room, state.players}}, state}
    else
      {:reply, {:error, :room_is_full}, state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    player_index = Enum.find_index(state.players, fn player -> player.id == player_id end)

    case {state.room.status, player_index} do
      {_, nil} ->
        Logger.warning("[#{__MODULE__}] Player who hasn't joined the room attempted to leave")
        {:ok, state}

      {:waiting, player_index} ->
        {player, players} = List.pop_at(state.players, player_index)
        broadcast(state.room.id, {:player_changed, :left, player.id})
        Logger.info("[#{__MODULE__}] Player left the room: #{inspect(player)}")
        room = Map.replace(state.room, :player_count, Enum.count(players))
        state = %{state | room: room, players: players}

        # When there are no more human players remaining, delete the room
        if has_active_human_players?(state) do
          Gensou.Lobby.update_room(state.room)
          {:reply, :ok, state}
        else
          {:stop, :normal, :ok, state}
        end

      {:playing, player_index} ->
        players =
          List.update_at(
            state.players,
            player_index,
            &Map.replace(&1, :disconnected, true)
          )

        player = Enum.at(players, player_index)
        Logger.warning("[#{__MODULE__}] Player disconnected: #{inspect(player)}")
        state = %{state | players: players}
        broadcast(state.room.id, {:player_changed, :disconnected, player.id})

        # When there are no more connected human players remaining, delete the room
        if has_active_human_players?(state) do
          Gensou.Lobby.update_room(state.room)
          {:reply, :ok, state}
        else
          {:stop, :normal, :ok, state}
        end
    end
  end

  def handle_call({:finish_game, player_id}, _from, state) do
    player_index = Enum.find_index(state.players, fn player -> player.id == player_id end)

    case player_index do
      nil ->
        Logger.warning(
          "[#{__MODULE__}] Player who hasn't joined the room attempted to conclude the game"
        )

        {:ok, state}

      player_index ->
        players =
          List.update_at(
            state.players,
            player_index,
            &Map.replace(&1, :finished, true)
          )

        player = Enum.at(players, player_index)
        state = %{state | players: players}
        Logger.warning("[#{__MODULE__}] Player finished the game: #{inspect(player)}")

        # When there are no more connected human players remaining, delete the room
        if has_active_human_players?(state) do
          Gensou.Lobby.update_room(state.room)
          {:reply, :ok, state}
        else
          {:stop, :normal, :ok, state}
        end
    end
  end

  def handle_call({:update_readiness, player_id, ready}, _from, state) do
    # TODO ensure that only the room host can change the state of other players
    player_index = Enum.find_index(state.players, fn player -> player.id == player_id end)

    players =
      if player_index == 0 do
        # When the room host updates readiness, it actually means
        # it should force everyone to become ready
        Enum.map(state.players, &Map.replace(&1, :ready, ready))
      else
        List.update_at(
          state.players,
          player_index,
          &Map.replace(&1, :ready, ready)
        )
      end

    player = Enum.at(players, player_index)
    Logger.info("[#{__MODULE__}] Player changed their state: #{inspect(player)}")
    state = %{state | players: players}
    player_state = if ready, do: :ready, else: :not_ready
    broadcast(state.room.id, {:player_changed, player_state, player.id})

    {:reply, :ok, state}
  end

  def handle_call({:update_loading_state, player_id, loading_state}, _from, state) do
    # TODO ensure that only the room host can change the state of other players
    player_index = Enum.find_index(state.players, fn player -> player.id == player_id end)

    players =
      List.update_at(
        state.players,
        player_index,
        &Map.replace(&1, :loading, loading_state)
      )

    all_players_loaded? =
      Enum.all?(players, fn player -> player.loading == :loaded or player.trip == "CPU" end)

    room =
      if all_players_loaded? do
        state.room
        |> Map.replace(:status, :playing)
        |> tap(&Gensou.Lobby.update_room/1)
      else
        state.room
      end

    player = Enum.at(players, player_index)
    state = %{state | room: room, players: players}
    Logger.info("[#{__MODULE__}] Player changed their loading state: #{inspect(player)}")
    broadcast(state.room.id, {:player_changed, loading_state, player.id})

    {:reply, :ok, state}
  end

  def handle_call({:add_game_event, game_event}, _from, state) do
    # TODO ensure that events are only sent on behalf of self
    # or CPU and disconnected players, by the host
    Logger.debug(
      "[#{__MODULE__}] New event from #{game_event.player_id}: #{inspect(game_event.data)}"
    )

    # TODO only correct the index when it's equal to the latest one
    game_event =
      if game_event.index != state.event_index do
        Logger.warning(
          "[#{__MODULE__}] Received event with invalid index #{game_event.index} (expected #{state.event_index})"
        )

        %{game_event | index: state.event_index}
      else
        game_event
      end

    state = %{state | events: [game_event | state.events], event_index: state.event_index + 1}
    broadcast(state.room.id, {:game_event, game_event})
    {:reply, :ok, state}
  end

  defp schedule_room_gc() do
    Process.send_after(self(), :gc, :timer.minutes(1))
  end

  defp has_active_human_players?(state) do
    Enum.any?(
      state.players,
      fn player ->
        player.trip != "CPU" and
          not player.disconnected and
          not player.finished
      end
    )
  end

  def address(room_id) do
    {:via, Registry, {Gensou.RoomRegistry, :room, room_id}}
  end

  def topic(room_id), do: "room:#{room_id}"

  def broadcast(room_id, event) do
    Phoenix.PubSub.broadcast(Gensou.PubSub, topic(room_id), event)
  end

  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(Gensou.PubSub, topic(room_id))
  end

  def unsubscribe(room_id) do
    Phoenix.PubSub.unsubscribe(Gensou.PubSub, topic(room_id))
  end

  def create(%Gensou.Model.Request.CreateRoom{} = settings) do
    result =
      DynamicSupervisor.start_child(
        Gensou.RoomSupervisor,
        {__MODULE__, settings: settings, strategy: :one_for_one, restart: :transient}
      )

    case result do
      {:ok, pid} ->
        {:ok, room} = get_info(pid)
        address = address(room.id)
        {:ok, {address, room}}

      error ->
        error
    end
  end

  def get_info(pid), do: call(pid, :get_info)
  def get_players(pid), do: call(pid, :get_players)
  def join(pid, player, password), do: call(pid, {:join, player, password})

  def rejoin(pid, player_id, last_event_index),
    do: call(pid, {:rejoin, player_id, last_event_index})

  def leave(pid, player_id), do: call(pid, {:leave, player_id})

  def update_readiness(pid, player_id, state),
    do: call(pid, {:update_readiness, player_id, state})

  def update_loading_state(pid, player_id, loading_state),
    do: call(pid, {:update_loading_state, player_id, loading_state})

  def add_cpu(pid, player), do: call(pid, {:add_cpu, player})
  def add_game_event(pid, game_event), do: call(pid, {:add_game_event, game_event})
  def finish_game(pid, player_id), do: call(pid, {:finish_game, player_id})
  def get_player(pid, player_id), do: call(pid, {:get_player, player_id})

  def find_player_in_all_games(player_id) do
    # FIXME not particularly efficient
    Registry.match(Gensou.RoomRegistry, :room, :_)
    |> Enum.map(fn {pid, room_id} ->
      case get_player(pid, player_id) do
        {:ok, player} -> {room_id, player}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp call(pid, msg) do
    case GenServer.whereis(pid) do
      nil -> {:error, :room_not_found}
      _ -> GenServer.call(pid, msg)
    end
  end
end
