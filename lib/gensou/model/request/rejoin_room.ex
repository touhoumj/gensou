defmodule Gensou.Model.Request.RejoinRoom do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :id, :integer, null: false
    field :last_event_index, :integer, default: 1
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:id, :last_event_index])
    |> validate_required([:id])
  end
end
