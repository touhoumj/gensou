defmodule Gensou.Model.Response.RejoinDetails do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    embeds_one :room, Gensou.Model.Room
    embeds_many :players, Gensou.Model.Player
    embeds_many :events, Gensou.Model.GameEvent
  end

  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [])
    |> cast_embed(:room)
    |> cast_embed(:players)
    |> cast_embed(:events)
  end
end
