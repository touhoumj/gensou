defmodule Gensou.Protocol do
  defimpl CBOR.Encoder,
    for: [
      Gensou.Protocol.Request,
      Gensou.Protocol.Response,
      Gensou.Protocol.Broadcast,
      Gensou.Model.Player.Stats
    ] do
    def encode_into(event, acc) do
      event
      |> Map.from_struct()
      |> CBOR.Encoder.encode_into(acc)
    end
  end

  defimpl CBOR.Encoder,
    for: [
      Gensou.Model.MOTD,
      Gensou.Model.Lobby,
      Gensou.Model.Room,
      Gensou.Model.Player,
      Gensou.Model.GameEvent
    ] do
    def encode_into(%schema{} = event, acc) do
      event
      |> schema.dump()
      |> CBOR.Encoder.encode_into(acc)
    end
  end
end
