defmodule Riffed.Server do
  @moduledoc ~S"""
  Provides a server and datastructure mappings to help you build thrift servers in Elixir. Macros
  dutifully work behind the scenes to give you near-seamless access to Thrift structures.

  *Riffed: Bridging the divide between Thrift and Elixir.*

  ## Usage

  The Thrift erlang implementation doesn't provide the ability to enumerate all defined RPC functions,
  so you need to tell Riffed which functions you'd like to expose in your server. After doing this, the
  Thrift metadata is interrogated and your return types are figured out and built for you. They're
  available for you to use in a module of your choosing.

  The example below assumes a thrift service called database defined in src/database_thrift.erl. The
  database exports select, delete and insert as functions. These functions take a string and a list of
  strings and return a ResultSet thrift object.

  You can also define an `after_start` function that will execute after the server has been started. The
  function takes a server_pid and the server_opts as arguments.

  Lastly, you can optionally define your own error handler to perform logic when clients disconnect,
  timeout, or do any other bad things.


        defmodule Server do
          use Riffed.Server, service: :database_thrift,
          structs: DB,
          functions: [select: &Handlers.select/2,
                      insert: &Handlers.insert/2,
                      delete: &Handlers.delete/2],

          server: {:thrift_socket_server,
                   port: 3306,
                   framed: true,
                   max: 5000,
                   socket_opts: [recv_timeout: 3000]
         },

         after_start: fn(server_pid, server_opts) ->
            ZKRegister.death_pact(server_pid, server_opts[:port])
         end,

         error_handler: &Handlers.handle_error/2

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

          def handle_error(_, :closed) do
            "Oh no, the client left!"
          end

          def handle_error(_, :timeout) do
            "Woah, the client disappeared!"
          end

          def handle_error(function_name, reason) do
            "Thrift exploded"
          end
        end

  ### Usage:

      Server.start_link


  """
  import Riffed.MacroHelpers
  alias Riffed.ThriftMeta, as: ThriftMeta
  alias Riffed.ThriftMeta.Meta, as: Meta

  defmacro __using__(opts) do
    quote do
      use Riffed.Callbacks
      use Riffed.Enumeration

      require Riffed.Server
      require Riffed.Struct
      import Riffed.Server

      @thrift_module unquote(opts[:service])
      @functions unquote(opts[:functions])
      @struct_module unquote(opts[:structs])
      @server unquote(opts[:server])
      @after_start unquote(Macro.escape(opts[:after_start]))
      @error_handler unquote(opts[:error_handler])
      @auto_import_structs unquote(Keyword.get(opts, :auto_import_structs, true))
      @before_compile Riffed.Server
    end
  end

  defp build_delegate_call(delegate_fn, params_meta) do
    delegate_info = :erlang.fun_info(delegate_fn)

    arg_list = build_arg_list(params_meta)

    {{:., [], [{:__aliases__, [alias: false],
                [delegate_info[:module]]}, delegate_info[:name]]}, [], arg_list}
  end

  defp build_handler(meta=%Meta{}, struct_module, thrift_fn_name, delegate_fn, fn_overrides) do

    function_meta = Meta.metadata_for_function(meta, thrift_fn_name)
    params_meta = function_meta[:params]
    reply_meta = function_meta[:reply] |> Riffed.Struct.to_riffed_type_spec
    tuple_args = build_handler_tuple_args(params_meta)
    delegate_call = build_delegate_call(delegate_fn, params_meta)
    casts = build_casts(thrift_fn_name, struct_module, params_meta, fn_overrides, :to_elixir)
    overridden_type = Riffed.Enumeration.get_overridden_type(thrift_fn_name, :return_type, fn_overrides, reply_meta)

    quote do
      def handle_function(unquote(thrift_fn_name), unquote(tuple_args)) do
        unquote_splicing(casts)
        rsp = unquote(delegate_call)
        |> unquote(struct_module).to_erlang(unquote(overridden_type))

        case rsp do
          :ok -> :ok
          _ -> {:reply, rsp}
        end
      end
    end
  end

  defp build_error_handler(nil) do
    quote do
      def handle_error(_, :timeout) do
        Lager.notice("Connection to client timed out.")
        {:ok, :timeout}
      end

      def handle_error(_, :closed) do
        {:ok, :closed}
      end

      def handle_error(name, reason) do
        Lager.error("Unhandled thrift error: #{name}, #{reason}")
        {:error, reason}
      end
    end
  end

  defp build_error_handler(delegate_fn) do
    quote do
      def handle_error(function_name, reason) do
        unquote(delegate_fn).(function_name, reason)
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
    overrides = Riffed.Enumeration.get_overrides(env.module)

    after_start = Module.get_attribute(env.module, :after_start) || quote do: fn (_, _) -> nil end
    error_handler = Module.get_attribute(env.module, :error_handler) |> build_error_handler

    function_handlers = Enum.map(functions,
      fn({fn_name, delegate}) ->
        build_handler(thrift_meta, struct_module, fn_name, delegate, overrides.functions) end)

    structs_keyword = ThriftMeta.Meta.structs_to_keyword(thrift_meta)

    if Module.get_attribute(env.module, :auto_import_structs)  do
      struct_module = quote do
        defmodule unquote(struct_module) do
          @build_cast_to_erlang true
          use Riffed.Struct, unquote(structs_keyword)
          unquote_splicing(Riffed.Callbacks.reconstitute(env.module))
          unquote_splicing(Riffed.Enumeration.reconstitute(env.module))
        end
      end
    else
      struct_module = quote do
      end
    end

    quote do
      unquote(struct_module)
      require Lager

      def start_link do
        default_opts = [service: unquote(thrift_module),
                        handler: unquote(env.module),
                        name: unquote(env.module)]
        opts = Keyword.merge(unquote(server_opts), default_opts)
        {:ok, server_pid} = unquote(server).start(opts)
        unquote(after_start).(server_pid, unquote(server_opts))
        {:ok, server_pid}
      end

      unquote(Riffed.Callbacks.default_to_erlang)
      unquote(Riffed.Callbacks.default_to_elixir)
      unquote_splicing(function_handlers)

      def handle_function(name, args) do
        raise "Handler #{inspect(name)} #{inspect(args)} Not Implemented"
      end

      unquote(error_handler)
    end
  end

end
