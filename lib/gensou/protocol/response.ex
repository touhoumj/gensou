defmodule Gensou.Protocol.Response do
  import Ecto.Changeset
  alias Gensou.Protocol.{Action, Request, Response}
  alias Gensou.Model

  @enforce_keys [:id, :action, :success, :error, :data]
  defstruct [:id, :action, :success, :error, :data]

  @type t :: %__MODULE__{
          id: String.t(),
          action: Action.t(),
          success: boolean(),
          error: String.t(),
          data: data() | nil
        }
  @type data :: Model.Lobby.t() | Model.Player.t() | Model.Response.PlayerList.t()

  def for_request(%Request{} = request, nil) do
    %Response{
      id: request.id,
      action: request.action,
      success: true,
      error: nil,
      data: nil
    }
  end

  def for_request(%Request{} = request, data) when is_struct(data) do
    %Response{
      id: request.id,
      action: request.action,
      success: true,
      error: nil,
      data: data
    }
  end

  def for_invalid_request(%Request{} = request, error) do
    %Response{
      id: request.id,
      action: request.action,
      success: false,
      error: error,
      data: nil
    }
  end

  def for_invalid_request(%Ecto.Changeset{} = changeset) do
    id = get_change(changeset, :id, Map.get(changeset.params, "id"))
    action = get_change(changeset, :action, Map.get(changeset.params, "action"))

    if is_nil(id) or is_nil(action) do
      {:error, :insufficient_request}
    else
      error =
        changeset
        |> traverse_errors(fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
        |> Enum.map_join(
          "\n",
          fn {key, msg} ->
            key_str = Enum.join(List.wrap(key), ".")
            msg_str = Enum.join(List.wrap(msg), " ")
            "#{key_str}: #{msg_str}"
          end
        )

      response = %Response{
        id: id,
        action: action,
        success: false,
        error: error,
        data: nil
      }

      {:ok, response}
    end
  end

  def to_binary(event) do
    CBOR.encode(event)
  end
end
