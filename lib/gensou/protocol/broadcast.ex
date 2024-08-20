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
          | :player_changed
          | :game_event

  @type data ::
          Model.MOTD.t()
          | Model.Lobby.t()
          | Model.GameEvent.t()
          | Model.Player.t()
          | Model.Response.PlayerChange.t()

  def to_binary(event) do
    CBOR.encode(event)
  end
end
