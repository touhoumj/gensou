defmodule Gensou.Model.Room do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :integer, null: false
    field :name, :string, null: false
    field :description, :string
    field :time, :integer, null: false
    field :has_password, :boolean, null: false
    field :table_name, :string, null: false
    field :password, :string, virtual: true
    field :enable_magic, :boolean, null: false
    field :allow_quick_join, :boolean, null: false

    field :game_length, Ecto.Enum,
      values: [yonma_tonpuusen: 1, yonma_hanchan: 2, sanma_hanchan: 3],
      embed_as: :dumped,
      null: false

    field :player_count, :integer, default: 0
    field :status, Ecto.Enum, values: [:waiting, :playing]
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :time,
      :has_password,
      :table_name,
      :password,
      :enable_magic,
      :allow_quick_join,
      :game_length,
      :player_count,
      :status
    ])
    |> validate_required([
      :id,
      :name,
      :time,
      :has_password,
      :table_name,
      :enable_magic,
      :allow_quick_join,
      :game_length,
      :status
    ])
  end

  def max_players(%__MODULE__{} = room) do
    case room.game_length do
      :yonma_tonpuusen -> 4
      :yonma_hanchan -> 4
      :sanma_hanchan -> 3
    end
  end
end
