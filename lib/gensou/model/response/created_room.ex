defmodule Gensou.Model.Response.CreatedRoom do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :integer, null: false
  end

  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:id])
    |> validate_required([:id])
  end
end
