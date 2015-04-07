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
      @before_compile Rift.Server
    end
  end

  def build_delegate_call(delegate_fn) do
    delegate_info = :erlang.fun_info(delegate_fn)

    arg_list = build_arg_list(delegate_info[:arity])

    {{:., [], [{:__aliases__, [alias: false],
                [delegate_info[:module]]}, delegate_info[:name]]}, [], arg_list}
  end

  defp build_handler(meta=%Meta{}, struct_module, server_module, thrift_fn_name, delegate_fn) do

    function_meta = Meta.metadata_for_function(meta, thrift_fn_name)
    params_meta = function_meta[:params]
    tuple_args = build_handler_tuple_args(params_meta)
    delegate_call = build_delegate_call(delegate_fn)
    casts = build_casts(struct_module, params_meta, :to_elixir)
    enum_casts = Rift.Enumeration.build_function_casts(server_module,
                                                       struct_module,
                                                       thrift_fn_name,
                                                       :to_elixir)

    quote do
      def handle_function(unquote(thrift_fn_name), unquote(tuple_args)) do
        unquote_splicing(casts)
        unquote_splicing(enum_casts)
        rsp = unquote(delegate_call)
        |> unquote(struct_module).to_erlang
        |> cast_return_value_to_erlang(unquote(thrift_fn_name))

        {:reply, unquote(struct_module).to_erlang(rsp)}
      end
    end
  end

  defmacro __before_compile__(env) do
    functions = Module.get_attribute(env.module, :functions)
    struct_module = Module.get_attribute(env.module, :struct_module)
    thrift_module = Module.get_attribute(env.module, :thrift_module)

    function_names = Enum.map(functions, fn({name, _}) -> name end)
    thrift_meta = ThriftMeta.extract(thrift_module, function_names)
    {server, server_opts}= Module.get_attribute(env.module, :server)

    handlers = Enum.map(functions,
      fn({fn_name, delegate}) ->
        build_handler(thrift_meta, struct_module, env.module, fn_name, delegate) end)

    structs_keyword = ThriftMeta.Meta.structs_to_keyword(thrift_meta)

    quote  do
      defmodule unquote(struct_module) do
        use Rift.Struct, unquote(structs_keyword)
        unquote_splicing(Rift.Callbacks.reconstitute(env.module))
        unquote_splicing(Rift.Enumeration.reconstitute(env.module))
      end

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

      unquote_splicing(Rift.Enumeration.build_cast_return_value_to_erlang(struct_module, env.module))
      unquote(Rift.Enumeration.generate_default_casts)
      unquote_splicing(handlers)

      def handle_function(name, args) do
        raise "Handler #{inspect(name)} #{inspect(args)} Not Implemented"
      end
    end
  end
end
