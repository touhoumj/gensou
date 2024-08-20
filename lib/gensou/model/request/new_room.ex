defmodule Gensou.Model.Request.NewRoom do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :name, :string, null: false
    field :description, :string
    field :time, :integer, null: false
    field :has_password, :boolean, null: false
    field :table_name, :string, null: false
    field :password, :string
    field :enable_magic, :boolean, null: false
    field :allow_quick_join, :boolean, null: false

    field :game_length, Ecto.Enum,
      values: [yonma_tonpuusen: 1, yonma_hanchan: 2, sanma_hanchan: 3],
      embed_as: :dumped,
      null: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [
      :name,
      :description,
      :time,
      :has_password,
      :table_name,
      :password,
      :enable_magic,
      :allow_quick_join,
      :game_length
    ])
    |> validate_required([
      :name,
      :time,
      :has_password,
      :table_name,
      :enable_magic,
      :allow_quick_join,
      :game_length
    ])
  end
end
