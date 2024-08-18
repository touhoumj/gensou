defmodule Gensou.Protocol.Request.JoinRoom do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :integer, null: false
    field :password, :string
    field :mode, :string # is this even needed
    embeds_one :player, Gensou.Model.Player
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:id, :password, :mode])
    |> validate_required([:id])
    |> cast_embed(:player, required: true)
  end
end
