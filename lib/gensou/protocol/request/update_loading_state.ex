defmodule Gensou.Protocol.Request.UpdateLoadingState do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :state, Ecto.Enum, values: [:not_loading, :loading, :loaded]
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast( attrs, [:state])
    |> validate_required([ :state ])
  end
end
