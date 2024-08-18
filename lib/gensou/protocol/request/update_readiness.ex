defmodule Gensou.Protocol.Request.UpdateReadiness do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :ready, :boolean, null: false
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:ready])
    |> validate_required([:ready])
  end
end
