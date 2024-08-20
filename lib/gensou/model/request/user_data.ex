defmodule Gensou.Model.Request.Auth do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :key, :string, null: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:key])
    |> validate_required([:key])
  end
end
