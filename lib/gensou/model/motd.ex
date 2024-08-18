defmodule Gensou.Model.MOTD do
  use Gensou.Schema

  @primary_key false
  typed_embedded_schema do
    field :messages, {:array, :string}
  end

  @impl Gensou.Schema
  def changeset(%__MODULE__{} = data, attrs) do
    data
    |> cast(attrs, [:messages])
    |> validate_required([:messages])
  end
end
