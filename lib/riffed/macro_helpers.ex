defmodule Riffed.MacroHelpers do
  @moduledoc false

  def build_arg_list(size, prefix \\ nil) when is_integer(size) do
    case size do
      0 -> []
      size ->
        Enum.map(1..size, fn(param_idx) ->
          :"#{prefix}arg_#{param_idx}"
          |> Macro.var(nil)
        end)
    end

  end

  def build_handler_tuple_args(param_meta) do
    args =  param_meta |> length |> build_arg_list
    {:{}, [], args}
  end

  def build_casts(function_name, struct_module, params_meta, overrides, cast_function) do
    params_meta
    |> Enum.map(&build_arg_cast(function_name, struct_module, &1, overrides, cast_function))
  end

  defp build_arg_cast(function_name, struct_module, param_meta, overrides, cast_function) do
    {index, param_type} = param_meta
    param_name = :"arg_#{abs(index)}"
    param_type = Riffed.Struct.to_riffed_type_spec(param_type)
    param_type = Riffed.Enumeration.get_overridden_type(function_name,
                                                      param_name,
                                                      overrides,
                                                      param_type)
    var = Macro.var(param_name, nil)

    quote do
      unquote(var) = unquote(struct_module).unquote(cast_function)(unquote(var),
                                                                   unquote(param_type))
    end
  end
end
