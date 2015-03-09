defmodule Rift.Server do
  require Rift.Struct

  defmodule State do
    defstruct structs: [], handlers: []

    def append_handler(state=%State{}, handler) do
      %State{state | handlers: [handler | state.handlers]}
    end

    def append_struct(state=%State{}, struct) do
      %State{state | structs: [struct | state.structs]}
    end

    def structs_to_keyword(state=%State{}) do
      Enum.reduce(state.structs, HashDict.new,
                fn([:struct, {thrift_module, module_name}],  dict) ->
                  Dict.update(dict, thrift_module, [module_name], fn(l) -> [module_name | l]
                              end)
                end)
      |> Enum.into(Keyword.new)
    end
  end

  defmacro __using__(opts) do
    quote do
      require Rift.Server
      require Rift.Struct
      import Rift.Server

      @thrift_module unquote(opts[:thrift_module])
      @functions unquote(opts[:functions])
      @struct_module unquote(opts[:struct_module])
      @server unquote(opts[:server])
      @before_compile Rift.Server
    end
  end

  def append_struct(state=%State{}, {:struct, info={module, struct_name}}) do
    # find out if our structs have nested structs by getting their info
    # and searching for them
    {:struct, struct_info} = :erlang.apply(module, :struct_info, [struct_name])
    state = Enum.reduce(struct_info, state, fn({_idx, info}, state) ->
                          append_struct(state, info)
                          end)
    State.append_struct(state, [:struct, info])
  end

  def append_struct(state=%State{}, _) do
    state
  end

  defp find_structs_in_list(state=%State{}, param_meta) when is_list(param_meta) do
    Enum.reduce(param_meta, state,
      fn({_order, param_type}, state) ->
        append_struct(state, param_type) end)
  end

  defp find_reply_structs(state=%State{}, reply_meta) do
    case reply_meta do
      {:struct, _struct_info} -> append_struct(state, reply_meta)
      _ -> state
    end
  end

  def build_arg_list(size) when is_integer(size) do
    Enum.map(1..size, fn(param_idx) ->
               param_name = String.to_atom("arg_#{param_idx}")
               {param_name, [], nil}
             end)
  end

  def build_handler_tuple_args(param_meta) do
    {:{}, [], build_arg_list(length(param_meta))}
  end

  defp build_arg_cast(name) do
    var = Macro.var(name, nil)
    quote do
      unquote(var) = Data.to_elixir(unquote(var))
    end
  end

  def build_delegate_call(delegate_fn) do
    delegate_info = :erlang.fun_info(delegate_fn)

    arg_list = build_arg_list(delegate_info[:arity])

    {{:., [], [{:__aliases__, [alias: false],
                [delegate_info[:module]]}, delegate_info[:name]]}, [], arg_list}
  end

  defp build_handler(state=%State{}, struct_module, thrift_module, thrift_fn_name, delegate_fn) do
    {:struct, param_meta} = thrift_module.function_info(thrift_fn_name, :params_type)
    reply_meta = thrift_module.function_info(thrift_fn_name, :reply_type)
    {:struct, exception_meta} = thrift_module.function_info(thrift_fn_name, :exceptions)

    state = state
    |> find_structs_in_list(param_meta)
    |> find_structs_in_list(exception_meta)
    |> find_reply_structs(reply_meta)

    tuple_args = build_handler_tuple_args(param_meta)
    delegate_call = build_delegate_call(delegate_fn)
    casts = param_meta
    |> Enum.with_index
    |> Enum.map(fn({_param_meta, idx}) ->
                  build_arg_cast(String.to_atom("arg_#{idx + 1}"))
                end)

    handler = quote do
      def handle_function(unquote(thrift_fn_name), unquote(tuple_args)) do
        unquote_splicing(casts)
        rsp = unquote(delegate_call)
        unquote(struct_module).to_erlang(rsp)
      end
    end
    State.append_handler(state, handler)
  end

  defmacro __before_compile__(env) do
    functions = Module.get_attribute(env.module, :functions)
    struct_module = Module.get_attribute(env.module, :struct_module)
    thrift_module = Module.get_attribute(env.module, :thrift_module)
    {server, server_opts}= Module.get_attribute(env.module, :server)

    state = Enum.reduce(functions, %State{},
      fn({fn_name, delegate}, state) ->
        build_handler(state, struct_module, thrift_module, fn_name, delegate) end)

    structs_keyword = State.structs_to_keyword(state)
    quote do
      defmodule unquote(struct_module) do
        use Rift.Struct, unquote(structs_keyword)
      end

      def start_link do
        default_opts = [service: unquote(thrift_module),
                        handler: unquote(env.module),
                        name: unquote(env.module)]
        opts = Keyword.merge(unquote(server_opts), default_opts)
        {:ok, server_pid} = unquote(server).start(opts)
        {:ok, server_pid}
      end

      unquote_splicing(state.handlers)
      def handle_function(_, _) do
        raise "Not Implemented"
      end
    end
  end


end
