defmodule Gensou.Model.Player do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :string, null: false
    field :name, :string, null: false
    field :trip, :string, null: false
    field :title_text, :string, null: false
    field :title_type, :integer, null: false
    field :character_id, :string, null: false
    field :character_skin, :integer, null: false
    embeds_one :stats, Gensou.Model.Player.Stats
    field :ready, :boolean, default: false
    field :disconnected, :boolean, default: false
    field :loading, Ecto.Enum, values: [:not_loading, :loading, :loaded], default: :not_loading
    field :finished, :boolean, default: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(
      attrs,
      [
        :id,
        :name,
        :trip,
        :title_text,
        :title_type,
        :character_id,
        :character_skin
      ]
    )
    |> validate_required([
      :id,
      :name,
      :trip,
      :title_type,
      :character_id,
      :character_skin
    ])
    |> cast_embed(:stats, required: true)
  end
end
