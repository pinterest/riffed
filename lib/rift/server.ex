defmodule Rift.Server do
  @moduledoc ~S"""
  ### Rift: Bridging the divide between Thrift and Elixir.

  This module provides a server and datastructure mappings to help you build thrift servers
  in Elixir. Macros dutifully work behind the scenes to give you near-seamless access to Thrift
  structures.

  ## Usage

  The Thrift erlang implementation doesn't provide the ability to enumerate all defined RPC functions,
  so you need to tell Rift which functions you'd like to expose in your server. After doing this, the
  Thrift metadata is interrogated and your return types are figured out and built for you. They're
  available for you to use in a module of your choosing.

  The example below assumes a thrift service called database defined in src/database_thrift.erl. The
  database exports select, delete and insert as functions. These functions take a string and a list of
  strings and return a ResultSet thrift object.


        defmodule Server do
          use Rift.Server, service: :database_thrift,
          structs: DB,
          functions: [select: &Handlers.select/2,
                      insert: &Handlers.insert/2,
                      delete: &Handlers.delete/2],

          server: {:thrift_socket_server,
                   port: 3306,
                   framed: true,
                   max: 5000,
                   socket_opts: [recv_timeout: 3000]
         }
        end

        defmodule Handlers do
          def select(query, args) do
            %DB.ResultSet.new(num_rows: 0, results: [])
          end

          def insert(query, args) do
            %DB.ResultSet.new(num_rows: 0, results: [])
          end

          def delete(query, args) do
            %DB.ResultSet.new(num_rows: 0, results: [])
          end
        end


  ### Usage:

        Server.start_link


  """
  defmodule State do
    defstruct structs: [], handlers: []

    def append_handler(state=%State{}, handler) do
      %State{state | handlers: [handler | state.handlers]}
    end

    def append_struct(state=%State{}, struct) do
      %State{state | structs: [struct | state.structs]}
    end

    def structs_to_keyword(state=%State{}) do
      state.structs
      |> Enum.uniq
      |> Enum.reduce(HashDict.new,
          fn([:struct, {thrift_module, module_name}],  dict) ->
            Dict.update(dict, thrift_module, [module_name], fn(l) -> [module_name | l]
                        end)
          end)
      |> Enum.into(Keyword.new)
    end
  end

  defmacro __using__(opts) do
    quote do
      use Rift.Callbacks

      require Rift.Server
      require Rift.Struct
      import Rift.Server

      @thrift_module unquote(opts[:service])
      @functions unquote(opts[:functions])
      @struct_module unquote(opts[:structs])
      @server unquote(opts[:server])
      @before_compile Rift.Server
    end
  end

  defp append_struct(state=%State{}, {:struct, info={module, struct_name}}) do
    # find out if our structs have nested structs by getting their info
    # and searching for them
    {:struct, struct_info} = :erlang.apply(module, :struct_info, [struct_name])
    state = Enum.reduce(struct_info, state, fn({_idx, info}, state) ->
                          append_struct(state, info)
                          end)
    State.append_struct(state, [:struct, info])
  end

  defp append_struct(state=%State{}, _) do
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
               "arg_#{param_idx}"
               |> String.to_atom
               |> Macro.var(nil)
             end)
  end

  defp build_handler_tuple_args(param_meta) do
    args =  param_meta |> length |> build_arg_list
    {:{}, [], args}
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

  defp reconstitute_callbacks(module) do
    module
    |> Module.get_attribute(:callbacks)
    |> Enum.map(
        fn(cb) ->
          quote do
            callback(unquote(cb.name), unquote(cb.guard)) do
              unquote(cb.body)
            end
          end
        end)
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

    quote  do
      defmodule unquote(struct_module) do
        use Rift.Struct, unquote(structs_keyword)
        unquote_splicing(reconstitute_callbacks(env.module))
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

      def handle_function(name, args) do
        raise "Handler #{inspect(name)} #{inspect(args)} Not Implemented"
      end
    end
  end
end
