defmodule Rift.Callbacks do
  @moduledoc ~S"""
  Callback implementation for structs.

  Presently, you may define `after_to_elixir` and `after_to_erlang`. after_to_elixir
  is called after a tuple is converted to an Elixir struct and after_to_erlang is called
  when an Elixir struct is turned into a tuple.
  """

  defmodule Callback do
    defstruct name: nil, guard: nil, body: nil

    def new(name, guard, body) do
      %Callback{name: name, guard: guard, body: body}
    end
  end

  defmacro __using__(_opts) do
    Module.register_attribute(__CALLER__.module, :callbacks, accumulate: true)
    quote do
      require Rift.Callbacks
      import Rift.Callbacks, only: [callback: 3]
    end
  end

  defmacro callback(callback_name, opts, do: body) do
    callback = Callback.new(callback_name, opts, body)
    Module.put_attribute(__CALLER__.module, :callbacks, callback)
  end

  def reconstitute(module) do
    module
    |> Module.get_attribute(:callbacks)
    |> Enum.map(&reconstitute_callback/1)
  end

  defp reconstitute_callback(callback=%Rift.Callbacks.Callback{}) do
    quote do
      callback(unquote(callback.name), unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  def default_to_elixir do
    quote do
      def to_elixir(:string, char_list) when is_list(char_list) do
        List.to_string(char_list)
      end

      def to_elixir(_, whatever) do
        to_elixir(whatever)
      end

      def to_elixir({k, v}) do
        {to_elixir(k), to_elixir(v)}
      end

      def to_elixir(t) when is_tuple(t) do
        first = elem(t, 0)
        case first do
          :dict ->
            Enum.into(:dict.to_list(t), HashDict.new, &to_elixir/1)
          :set ->
            Enum.into(:sets.to_list(t), HashSet.new, &to_elixir/1)
          _ ->
            t
            |> Tuple.to_list
            |> Enum.map(&to_elixir/1)
            |> List.to_tuple
        end
      end

      def to_elixir(l) when is_list(l) do
        Enum.map(l, &to_elixir(&1))
      end

      def to_elixir(x) do
        x
      end
    end
  end

  def default_to_erlang do
    quote do
      def to_erlang(:string, bitstring) when is_bitstring(bitstring) do
        String.to_char_list(bitstring)
      end

      def to_erlang(_, whatever) do
        to_erlang(whatever)
      end

      def to_erlang({k, v}) do
        {to_erlang(k), to_erlang(v)}
      end

      def to_erlang(l) when is_list(l) do
        Enum.map(l, &to_erlang(&1))
      end

      def to_erlang(d=%HashDict{}) do
        d
        |> Dict.to_list
        |> Enum.map(&to_erlang/1)
        |> :dict.from_list
      end

      def to_erlang(hs=%HashSet{}) do
        hs
        |> Set.to_list
        |> Enum.map(&to_erlang/1)
        |> :sets.from_list
      end

      def to_erlang(x) do
        x
      end

    end
  end

  def build(module, _filter \\ fn(_callback) -> true end) do
    defined_callbacks = module
    |> Module.get_attribute(:callbacks)
    |> Enum.map(fn(callback) ->
                  build_internal(callback.name, callback) end)

    quote do
      unquote_splicing(defined_callbacks)
      defp after_to_elixir(x) do
        x
      end

      defp after_to_erlang(x) do
        x
      end
    end
  end

  defp build_internal(:after_to_elixir, callback=%Callback{}) do
    quote do
      defp after_to_elixir(unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  defp build_internal(:after_to_erlang, callback=%Callback{}) do
    quote do
      defp after_to_erlang(unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  defp build_internal(unknown, _) do
    raise "Warning: undefined callback #{unknown}"
  end

end
