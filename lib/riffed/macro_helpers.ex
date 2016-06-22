defmodule Riffed.MacroHelpers do
  @moduledoc false
  def build_arg_list(param_meta) do
    param_meta
    |> Enum.map(&build_arg(&1))
  end

  def build_handler_tuple_args(param_meta) do
    args =  build_arg_list(param_meta)
    {:{}, [], args}
  end

  def build_casts(function_name, struct_module, params_meta, overrides, cast_function) do
    params_meta
    |> Enum.map(&build_arg_cast(function_name, struct_module, &1, overrides, cast_function))
  end

  defp build_arg({index, _type}=arg) do
    Macro.var(:"arg_#{abs(index)}", nil)
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
