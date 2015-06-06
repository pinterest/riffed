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
  import Rift.MacroHelpers
  alias Rift.ThriftMeta, as: ThriftMeta
  alias Rift.ThriftMeta.Meta, as: Meta

  defmacro __using__(opts) do
    quote do
      use Rift.Callbacks
      use Rift.Enumeration

      require Rift.Server
      require Rift.Struct
      import Rift.Server

      @thrift_module unquote(opts[:service])
      @functions unquote(opts[:functions])
      @struct_module unquote(opts[:structs])
      @server unquote(opts[:server])
      @auto_import_structs unquote(Keyword.get(opts, :auto_import_structs, true))
      @before_compile Rift.Server
    end
  end

  defp build_delegate_call(delegate_fn) do
    delegate_info = :erlang.fun_info(delegate_fn)

    arg_list = build_arg_list(delegate_info[:arity])

    {{:., [], [{:__aliases__, [alias: false],
                [delegate_info[:module]]}, delegate_info[:name]]}, [], arg_list}
  end

  defp build_handler(meta=%Meta{}, struct_module, thrift_fn_name, delegate_fn, fn_overrides) do

    function_meta = Meta.metadata_for_function(meta, thrift_fn_name)
    params_meta = function_meta[:params]
    reply_meta = function_meta[:reply] |> Rift.Struct.to_rift_type_spec
    tuple_args = build_handler_tuple_args(params_meta)
    delegate_call = build_delegate_call(delegate_fn)
    casts = build_casts(thrift_fn_name, struct_module, params_meta, fn_overrides, :to_elixir)
    overridden_type = Rift.Enumeration.get_overridden_type(thrift_fn_name, :return_type, fn_overrides, reply_meta)

    quote do
      def handle_function(unquote(thrift_fn_name), unquote(tuple_args)) do
        unquote_splicing(casts)
        rsp = unquote(delegate_call)
        |> unquote(struct_module).to_erlang(unquote(overridden_type))

        {:reply, rsp}
      end
    end
  end

  defmacro __before_compile__(env) do
    functions = Module.get_attribute(env.module, :functions)
    struct_module = Module.get_attribute(env.module, :struct_module)
    thrift_module = Module.get_attribute(env.module, :thrift_module)

    function_names = Enum.map(functions, fn({name, _}) -> name end)
    thrift_meta = ThriftMeta.extract(thrift_module, function_names)

    {server, server_opts} = Module.get_attribute(env.module, :server)
    overrides = Rift.Enumeration.get_overrides(env.module)


    handlers = Enum.map(functions,
      fn({fn_name, delegate}) ->
        build_handler(thrift_meta, struct_module, fn_name, delegate, overrides.functions) end)

    structs_keyword = ThriftMeta.Meta.structs_to_keyword(thrift_meta)

    if Module.get_attribute(env.module, :auto_import_structs)  do
      struct_module = quote do
        defmodule unquote(struct_module) do
          @build_cast_to_erlang true
          use Rift.Struct, unquote(structs_keyword)
          unquote_splicing(Rift.Callbacks.reconstitute(env.module))
          unquote_splicing(Rift.Enumeration.reconstitute(env.module))
        end
      end
    else
      struct_module = quote do
      end
    end

    quote do
      unquote(struct_module)

      def start_link do
        default_opts = [service: unquote(thrift_module),
                        handler: unquote(env.module),
                        name: unquote(env.module)]
        opts = Keyword.merge(unquote(server_opts), default_opts)
        {:ok, server_pid} = unquote(server).start(opts)
        {:ok, server_pid}
      end

      unquote(Rift.Callbacks.default_to_erlang)
      unquote(Rift.Callbacks.default_to_elixir)
      unquote_splicing(handlers)

      def handle_function(name, args) do
        raise "Handler #{inspect(name)} #{inspect(args)} Not Implemented"
      end
    end
  end

end
