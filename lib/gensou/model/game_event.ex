defmodule Gensou.Model.GameEvent do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :index, :integer, null: false
    field :player_id, :string, null: false
    field :seat, :integer, null: false
    field :data, :map, null: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:index, :player_id, :seat, :data])
    |> validate_required([:index, :player_id, :seat, :data])
  end
end
