defmodule Gensou.Model.Response.PlayerChange do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :string, null: false
    # join event needs a lot more data so it is separate
    field :state, Ecto.Enum,
      values: [:ready, :not_ready, :left, :disconnected, :reconnected, :loading, :loaded]
  end

  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:id, :state])
    |> validate_required([:id, :state])
  end
end
