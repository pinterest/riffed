defmodule Rift.ThriftMeta do
  defmodule Meta do
    defstruct structs: [], meta_by_function: HashDict.new

    def append_struct(meta=%Meta{}, struct) do
      %Meta{meta | structs: [struct | meta.structs]}
    end

    def structs_to_keyword(meta=%Meta{}) do
      meta.structs
      |> Enum.uniq
      |> Enum.reduce(HashDict.new,
          fn([:struct, {thrift_module, module_name}],  dict) ->
            Dict.update(dict, thrift_module, [module_name], fn(l) -> [module_name | l]
                        end)
          end)
      |> Enum.into(Keyword.new)
    end

    def add_metadata_for_function(meta=%Meta{}, function_name, metadata) do
      new_metadata = Dict.put(meta.meta_by_function, function_name, metadata)

      %Meta{meta | meta_by_function: new_metadata}
    end

    def metadata_for_function(meta=%Meta{}, function_name) do
      meta.meta_by_function[function_name]
    end
  end


  def extract(thrift_module, list_of_functions) do
    Enum.reduce(list_of_functions, %Meta{},
      fn(fn_name, meta) ->
        extract_metadata(meta, thrift_module, fn_name)
      end)
  end


  defp extract_metadata(meta=%Meta{}, thrift_module, thrift_fn_name) do
    {:struct, param_meta} = thrift_module.function_info(thrift_fn_name, :params_type)
    reply_meta = thrift_module.function_info(thrift_fn_name, :reply_type)
    {:struct, exception_meta} = thrift_module.function_info(thrift_fn_name, :exceptions)
    meta
    |> find_struct(param_meta)
    |> find_struct(exception_meta)
    |> find_struct(reply_meta)
    |> Meta.add_metadata_for_function(thrift_fn_name, [params: param_meta,
                                                       exceptions: exception_meta,
                                                       reply: reply_meta])
  end

  defp find_struct(meta=%Meta{}, param_meta) when is_list(param_meta) do
    Enum.reduce(param_meta, meta,
      fn({_order, param_type}, meta) ->
        find_struct(meta, param_type) end)
  end

  defp find_struct(meta=%Meta{}, {:map, key_type, val_type}) do
    meta
    |> find_struct(key_type)
    |> find_struct(val_type)
  end

  defp find_struct(meta=%Meta{}, {:set, item_type}) do
    find_struct(meta, item_type)
  end

  defp find_struct(meta=%Meta{}, {:list, item_type}) do
    find_struct(meta, item_type)
  end

  defp find_struct(meta=%Meta{}, {:struct, info={module, struct_name}}) do
    # find out if our structs have nested structs by getting their info
    # and searching for them
    {:struct, struct_info} = :erlang.apply(module, :struct_info, [struct_name])

    Enum.reduce(struct_info, meta, fn({_idx, info}, meta) ->
                         find_struct(meta, info)
                       end)
    |> Meta.append_struct([:struct, info])
  end

  defp find_struct(meta=%Meta{}, _) do
    meta
  end
end
