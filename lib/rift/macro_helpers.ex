defmodule Rift.MacroHelpers do

  def build_arg_list(size) when is_integer(size) do
    case size do
      0 -> []
      size ->
          Enum.map(0..size - 1, fn(param_idx) ->
                     "arg_#{param_idx + 1}"
                     |> String.to_atom
                     |> Macro.var(nil)
                   end)
    end
  end

  def build_handler_tuple_args(param_meta) do
    args =  param_meta |> length |> build_arg_list
    {:{}, [], args}
  end

  def build_casts(struct_module, params_meta, cast_function) do
    params_meta
    |> Enum.with_index
    |> Enum.map(fn({_param_meta, idx}) ->
                  build_arg_cast(struct_module, String.to_atom("arg_#{idx + 1}"), cast_function)
                end)
  end

  defp build_arg_cast(struct_module, name, cast_function) do
    var = Macro.var(name, nil)
    quote do
      unquote(var) = unquote(struct_module).unquote(cast_function)(unquote(var))
    end
  end
end
