defmodule Gensou.Protocol.Request do
  import Ecto.Changeset
  alias Gensou.Protocol.{Action, Request}

  defstruct [:id, :action, :data]

  @type t :: %__MODULE__{
          id: String.t(),
          action: Action.t(),
          data: data()
        }
  @type action :: Action.t()
  @type data ::
          Request.Auth.t()
          | Request.NewRoom.t()
          | Request.JoinRoom.t()
          | Request.UpdateReadiness.t()
          | Request.UpdateLoadingState.t()
          | Gensou.Model.Player.t()
          | Gensou.Model.GameEvent.t()
          | nil

  @ecto_types %{
    id: :string,
    success: :boolean,
    action: Action.ecto_type(),
    data: :map
  }

  def new!(attrs) when is_non_struct_map(attrs) do
    attrs
    |> changeset()
    |> Ecto.Changeset.apply_action!(:data)
  end

  def new(attrs) when is_non_struct_map(attrs) do
    attrs
    |> changeset()
    |> Ecto.Changeset.apply_action(:data)
  end

  def changeset(attrs) when is_non_struct_map(attrs) do
    __MODULE__
    |> struct()
    |> changeset(attrs)
  end

  def changeset(%__MODULE__{} = data, attrs) when is_non_struct_map(attrs) do
    changeset =
      {data, @ecto_types}
      |> cast(attrs, Map.keys(@ecto_types))
      |> validate_required([:id, :action])

    action = get_field(changeset, :action)

    case schema_for_action(action) do
      :error ->
        changeset

      {:ok, nil} ->
        put_change(changeset, :data, nil)

      {:ok, mod} ->
        data = get_change(changeset, :data, %{})
        data_changeset = mod.changeset(data)

        if data_changeset.valid? do
          put_change(changeset, :data, apply_action!(data_changeset, :data))
        else
          for {key, {message, meta}} <- flatten_errors(data_changeset), reduce: changeset do
            acc -> add_error(acc, [:data | key], message, meta)
          end
        end
    end
  end

  def flatten_errors(changeset) do
    changeset
    |> traverse_errors(& &1)
    |> flatten_errors([])
  end

  def flatten_errors(errors, key_path) when is_map(errors) do
    Enum.flat_map(errors, fn {key, value} ->
      flatten_errors(value, key_path ++ [key])
    end)
  end

  def flatten_errors(errors, key_path) when is_list(errors) do
    for error <- errors do
      {key_path, error}
    end
  end

  def schema_for_action(action) do
    case action do
      :auth -> {:ok, Request.Auth}
      :get_lobby -> {:ok, nil}
      :leave_lobby -> {:ok, nil}
      :create_room -> {:ok, Request.NewRoom}
      :join_room -> {:ok, Request.JoinRoom}
      :leave_room -> {:ok, nil}
      :update_readiness -> {:ok, Request.UpdateReadiness}
      :update_loading_state -> {:ok, Request.UpdateLoadingState}
      :add_cpu -> {:ok, Gensou.Model.Player}
      :add_game_event -> {:ok, Gensou.Model.GameEvent}
      :finish_game -> {:ok, nil}
      _ -> :error
    end
  end

  def from_binary(bin) do
    with {:ok, message, _} <- CBOR.decode(bin) do
      new(message)
    end
  end

  def to_binary(event) do
    CBOR.encode(event)
  end
end
