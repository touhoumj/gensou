defmodule Gensou.Protocol.Broadcast do
  alias Gensou.Model

  @enforce_keys [:channel, :data]
  defstruct [:channel, :data]

  @type t :: %__MODULE__{
          channel: channel(),
          data: data() | nil
        }

  @type channel ::
          :motd
          | :lobby_changed
          | :players_changed
          | :player_loading_state
          | :game_event
          | :player_disconnected

  @type data ::
          Model.MOTD.t()
          | Model.Lobby.t()
          | list(Model.Player.t())
          | Model.GameEvent.t()
          | Model.Player.t()

  def to_binary(event) do
    CBOR.encode(event)
  end
end
