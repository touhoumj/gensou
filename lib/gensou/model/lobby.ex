defmodule Gensou.Model.Lobby do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    embeds_many :rooms, Gensou.Model.Room
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [])
    |> cast_embed(:rooms)
  end
end
