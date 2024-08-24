defmodule Gensou.Protocol.Action do
  @type t ::
          :auth
          | :join_lobby
          | :leave_lobby
          | :create_room
          | :join_room
          | :rejoin_room
          | :quick_join
          | :leave_room
          | :add_cpu
          | :update_readiness
          | :update_loading_state
          | :add_game_event
          | :finish_game

  @ecto_type {:parameterized,
              {Ecto.Enum,
               Ecto.Enum.init(
                 values: [
                   :auth,
                   :join_lobby,
                   :leave_lobby,
                   :create_room,
                   :join_room,
                   :rejoin_room,
                   :quick_join,
                   :leave_room,
                   :add_cpu,
                   :update_readiness,
                   :update_loading_state,
                   :add_game_event,
                   :finish_game
                 ]
               )}}

  def ecto_type(), do: @ecto_type
end
