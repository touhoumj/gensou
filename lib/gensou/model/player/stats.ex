defmodule Gensou.Model.Player.Stats do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :total_games, :integer, null: false, default: 0
    field :wins, :integer, null: false, default: 0
    field :points, :integer, null: false, default: 0
  end

  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:total_games, :wins, :points])
  end
end
