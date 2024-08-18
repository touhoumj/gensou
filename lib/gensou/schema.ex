defmodule Gensou.Schema do
  @callback new!(map()) :: Ecto.Schema.t()
  @callback new(map()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  @callback changeset(struct(), map()) :: Ecto.Changeset.t()

  defmacro __using__(_opts) do
    quote do
      use TypedEctoSchema
      import Ecto.Changeset

      @behaviour Gensou.Schema

      @impl Gensou.Schema
      def new!(attrs) when is_non_struct_map(attrs) do
        attrs
        |> changeset()
        |> Ecto.Changeset.apply_action!(:data)
      end

      @impl Gensou.Schema
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

      def dump(%mod{} = data) do
        mod.__to_map__(data)
      end

      def load(map, mod) do
        mod.__from_map__(map)
      end

      def __to_map__(data) do
        __MODULE__.__schema__(:fields)
        |> Enum.map(
          &{__MODULE__.__schema__(:field_source, &1), &1, __MODULE__.__schema__(:type, &1)}
        )
        |> Enum.map(fn {map_key, str_field, type} ->
          {map_key, data |> Map.fetch!(str_field), type}
        end)
        |> Enum.map(fn {map_key, str_value, type} ->
          {map_key, Ecto.Type.dump(type, str_value)}
        end)
        |> Enum.map(fn
          {map_key, {:ok, value}} -> {map_key, value}
        end)
        |> Enum.into(%{})
      end

      def __from_map__(map) do
        map =
          __MODULE__.__schema__(:fields)
          |> Enum.map(
            &{&1, __MODULE__.__schema__(:field_source, &1), __MODULE__.__schema__(:type, &1)}
          )
          |> Enum.map(fn {str_field, map_key, type} -> {str_field, map[map_key], type} end)
          |> Enum.map(fn {str_field, orig_value, type} ->
            {str_field, Ecto.Type.load(type, orig_value)}
          end)
          |> Enum.map(fn
            {str_field, {:ok, value}} -> {str_field, value}
          end)
          |> Enum.into(%{})

        struct!(__MODULE__, map)
      end
    end
  end
end
