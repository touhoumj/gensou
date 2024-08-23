defmodule Gensou.Model.Request.Auth do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :game_version, :string, null: false
    field :serial_key, :string, null: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:game_version, :serial_key])
    |> validate_required([:game_version, :serial_key])
  end
end
