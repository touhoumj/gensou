defmodule GensouWeb.GameSocket do
  @behaviour WebSock
  require Logger
  alias Gensou.Model
  alias Gensou.Protocol.{Request, Response, Broadcast}

  @impl WebSock
  def init(state) do
    state =
      Map.merge(
        %{
          player_id: nil,
          room_id: nil,
          room_address: nil,
          subscribed_to_lobby: false
        },
        state
      )

    Phoenix.PubSub.subscribe(Gensou.PubSub, "debug")
    send(self(), :motd)
    Logger.info("[#{__MODULE__}] New client #{:inet.ntoa(state.remote_ip)}.")
    {:ok, state}
  end

  @impl WebSock
  def terminate(reason, state) do
    Logger.info(
      "[#{__MODULE__}] Connection closed: #{:inet.ntoa(state.remote_ip)}. Reason: #{inspect(reason)}"
    )

    if !is_nil(state.room_address) and !is_nil(state.player_id) do
      Gensou.Room.leave(state.room_address, state.player_id)
    end

    :ok
  end

  @impl WebSock
  def handle_in({raw_packet, [opcode: :binary]}, state) do
    result =
      case Request.from_binary(raw_packet) do
        {:ok, request} ->
          Logger.debug("[#{__MODULE__}] Received: #{inspect(request)}")
          handle_request(request, state)

        {:error, %Ecto.Changeset{} = changeset} ->
          Logger.warning("[#{__MODULE__}] Received bad request: #{inspect(changeset)}")
          handle_bad_request(changeset, state)

        {:error, error}
        when error in [:cbor_function_clause_error, :cbor_match_error, :cbor_decoder_error] ->
          Logger.warning("[#{__MODULE__}] Couldn't decode packet: #{inspect(error)}")
          {:ok, state}
      end

    maybe_encode_result(result)
  end

  # Ignore everything else
  def handle_in(_message, state) do
    {:ok, state}
  end

  def handle_bad_request(changeset, state) do
    case Response.for_invalid_request(changeset) do
      {:ok, response} ->
        {:push, {:binary, response}, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  @spec handle_request(Request.t(), WebSock.state()) ::
          WebSock.handle_result()
  def handle_request(%{action: :auth} = request, state) do
    player_id =
      request.data.key
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    state = %{state | player_id: player_id}
    response = Response.for_request(request, nil)
    {:push, {:binary, response}, state}
  end

  def handle_request(request, %{player_id: nil} = state) do
    response =
      Response.for_invalid_request(
        request,
        "Couldn't process the request.\n" <>
          "Player ID is not known for this connection."
      )

    {:push, {:binary, response}, state}
  end

  def handle_request(%{action: :join_lobby} = request, state) do
    {:ok, lobby} = Gensou.Lobby.get_info()
    response = Response.for_request(request, lobby)
    {:push, {:binary, response}, maybe_subscribe_to_lobby(state)}
  end

  def handle_request(%{action: :leave_lobby} = request, state) do
    Gensou.Lobby.unsubscribe()
    state = %{state | subscribed_to_lobby: false}
    response = Response.for_request(request, nil)
    {:push, {:binary, response}, state}
  end

  def handle_request(%{action: :create_room} = request, state) do
    {:ok, {_room_pid, room}} = Gensou.Room.create(request.data)
    created_room = Gensou.Model.Response.CreatedRoom.new!(%{id: room.id})
    response = Response.for_request(request, created_room)
    {:push, {:binary, response}, state}
  end

  def handle_request(%{action: :join_room} = request, state) do
    # Will crash the socket when attempting to join a non-existent room
    # which is probably okay
    room_address = Gensou.Room.address(request.data.id)

    case Gensou.Room.join(room_address, request.data.player, request.data.password) do
      {:ok, {room, players}} ->
        state = %{
          state
          | player_id: request.data.player.id,
            room_id: room.id,
            room_address: room_address
        }

        :ok = Gensou.Room.subscribe(request.data.id)
        player_list = %Model.Response.PlayerList{players: players}
        response = {:binary, Response.for_request(request, player_list)}
        {:push, response, state}

      {:error, :not_found} ->
        request
        |> Response.for_invalid_request("Room not found")
        |> into_push(state)

      {:error, :room_is_full} ->
        request
        |> Response.for_invalid_request("Room is full")
        |> into_push(state)
    end
  end

  def handle_request(%{action: :leave_room} = request, state) do
    Gensou.Room.unsubscribe(state.room_id)
    Gensou.Room.leave(state.room_address, state.player_id)
    state = %{state | room_id: nil, room_address: nil}
    response = Response.for_request(request, nil)
    {:push, {:binary, response}, state}
  end

  def handle_request(%{action: :update_readiness} = request, state) do
    # TODO handle errors
    :ok =
      Gensou.Room.update_readiness(
        state.room_address,
        state.player_id,
        request.data.ready
      )

    request
    |> Response.for_request(nil)
    |> into_push(state)
  end

  def handle_request(%{action: :update_loading_state} = request, state) do
    # TODO handle errors
    :ok =
      Gensou.Room.update_loading_state(
        state.room_address,
        state.player_id,
        request.data.state
      )

    request
    |> Response.for_request(nil)
    |> into_push(state)
  end

  def handle_request(%{action: :add_cpu} = request, state) do
    # TODO handle errors
    {:ok, {room, _players}} = Gensou.Room.add_cpu(state.room_address, request.data)

    request
    |> Response.for_request(room)
    |> into_push(state)
  end

  def handle_request(%{action: :add_game_event} = request, state) do
    # TODO handle errors
    # TODO don't reuse request structs
    :ok = Gensou.Room.add_game_event(state.room_address, request.data)

    request
    |> Response.for_request(nil)
    |> into_push(state)
  end

  def handle_request(%{action: :finish_game} = request, state) do
    # TODO handle errors
    :ok = Gensou.Room.finish_game(state.room_address, state.player_id)
    Gensou.Room.unsubscribe(state.room_id)
    state = %{state | room_id: nil, room_address: nil}

    request
    |> Response.for_request(nil)
    |> into_push(state)
  end

  def handle_request(request, state) do
    Logger.debug("[#{__MODULE__}] Unhandled request: #{inspect(request)}")
    {:ok, state}
  end

  @impl WebSock
  def handle_info(:motd, state) do
    messages = ["Connected to Gensou server #{state.host}:#{state.port}"]
    data = Model.MOTD.new!(%{messages: messages})

    %Broadcast{channel: :motd, data: data}
    |> into_push(state)
    |> maybe_encode_result()
  end

  def handle_info({:global, msg}, state) do
    Logger.debug("Pushing #{inspect(msg)}")
    {:push, {:binary, CBOR.encode(msg)}, state}
  end

  def handle_info({:lobby_changed, lobby}, state) do
    # TODO replace with smaller updates
    %Broadcast{channel: :lobby_changed, data: lobby}
    |> into_push(state)
    |> maybe_encode_result()
  end

  def handle_info({:player_joined, player}, state) do
    %Broadcast{channel: :player_joined, data: player}
    |> into_push(state)
    |> maybe_encode_result()
  end

  def handle_info({:player_changed, kind, player_id}, state) do
    player_change = Model.Response.PlayerChange.new!(%{id: player_id, state: kind})

    %Broadcast{channel: :player_changed, data: player_change}
    |> into_push(state)
    |> maybe_encode_result()
  end

  def handle_info({:game_event, event}, state) do
    # FIXME don't reuse request structs
    %Broadcast{channel: :game_event, data: event}
    |> into_push(state)
    |> maybe_encode_result()
  end

  def handle_info(term, state) do
    Logger.debug("[#{__MODULE__}] Unhandled event: #{inspect(term)}")
    {:ok, state}
  end

  defp into_push(message, state) do
    {:push, {:binary, message}, state}
  end

  defp maybe_subscribe_to_lobby(state) do
    if state.subscribed_to_lobby do
      state
    else
      :ok = Gensou.Lobby.subscribe()
      %{state | subscribed_to_lobby: true}
    end
  end

  defp maybe_encode_result(result) do
    case result do
      {:push, messages, state} when is_list(messages) ->
        encoded_messages =
          for message <- messages do
            case message do
              {:binary, message} -> {:binary, CBOR.encode(message)}
              _ -> message
            end
          end

        {:push, encoded_messages, state}

      {:push, {:binary, message}, state} ->
        {:push, {:binary, CBOR.encode(message)}, state}

      _ ->
        result
    end
  end
end
