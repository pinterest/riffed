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

  defmacro __using__(opts) do
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

  def build(module, filter \\ fn(callback) -> true end) do
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
