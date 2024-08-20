defmodule Gensou.Model.Response.PlayerList do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    embeds_many :players, Gensou.Model.Player
  end

  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [])
    |> cast_embed(:players)
  end
end
