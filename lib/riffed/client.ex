defmodule Riffed.Client do
  @moduledoc ~S"""
  Provides a client wrapper for the `:thrift_client` erlang module.

  ## Usage
  The Erlang Thrift client implementation doesn't provide useful Elixir mappings, nor does it gracefully handle socket termination. Riffed's wrapper does, dutifully converting between Elixir and thrift for you.

      defmodule Client do
        use Riffed.Client, structs: Models,
        client_opts: [host: "localhost",
                      port: 1234567,
                      framed: true,
                      retries: 1],
        service: :my_library_thrift,
        import [:configure,
                :create,
                :update,
                :delete]

        defenum UserState do
          :active -> 1
          :inactive -> 2
          :banned -> 3
        end

        enumerize_struct(User, state: UserState)
      end

  In the above example, you can see that we've imported the functions `configure`, `create`, `update`, and `delete`. Riffed generates helper functions in the `Client` module that convert to and from Elixir. To use the client, simply invoke:

      Client.start_link

      Client.configure("config", 234)
      Client.create(Models.user.new(first_name: "Stinky", last_name: "Stinkman")
      Client.close

  The Elixir bitstrings will be automatically converted to erlang char lists when being sent to the thrift client, and char lists from the client will be automatically converted to bitstrings when returned *by* the thrift client. Riffed looks at your thrift definitions to find out when this should happen, so it's safe.
  """
  import Riffed.MacroHelpers
  import Riffed.ThriftMeta, only: [extract: 2]
  alias Riffed.ThriftMeta.Meta, as: Meta

  defmacro __using__(opts) do
    struct_module_name = opts[:structs]
    client_opts = opts[:client_opts]
    thrift_module = opts[:service]
    functions = opts[:import]

    quote do
      use Riffed.Callbacks
      use Riffed.Enumeration

      @struct_module unquote(struct_module_name)
      @client_opts unquote(client_opts)
      @thrift_module unquote(thrift_module)
      @functions unquote(functions)
      @auto_import_structs unquote(Keyword.get(opts, :auto_import_structs, true))
      @before_compile Riffed.Client
    end
  end

  defp build_exception_handlers(exception_type, struct_module) do
    {_seq, struct_def={:struct, {thrift_struct_module, exception_name}}} = exception_type
    {:struct, detailed_meta} = :erlang.apply(thrift_struct_module, :struct_info_ext, [exception_name])
    params = build_arg_list(Enum.count(detailed_meta), "_")
    |> List.insert_at(0, exception_name)

    args = {:{}, [], params}

    quote do
      defp raise_exception(ex=unquote(args)) do
        ex = unquote(struct_module).to_elixir(ex, unquote(struct_def))
        raise ex
      end
    end
  end

  defp build_client_function(thrift_metadata, struct_module, function_name, overrides) do
    function_meta = Meta.metadata_for_function(thrift_metadata, function_name)
    param_meta = function_meta[:params]
    exception_meta = function_meta[:exceptions]
    reply_meta = function_meta[:reply] |> Riffed.Struct.to_riffed_type_spec
    reply_meta = Riffed.Enumeration.get_overridden_type(function_name, :return_type, overrides, reply_meta)

    arg_list = build_arg_list(length(param_meta))
    {:{}, _, list_args} = build_handler_tuple_args(param_meta)
    casts = build_casts(function_name, struct_module, param_meta, overrides, :to_erlang)
    exception_handlers = exception_meta
    |> Enum.map(&build_exception_handlers(&1, struct_module))

    quote do

      unquote_splicing(exception_handlers)

      def unquote(function_name)(client_pid, unquote_splicing(arg_list))
        when is_pid(client_pid) do
          unquote_splicing(casts)
          rv = GenServer.call(client_pid, {unquote(function_name), unquote(list_args)})
          case rv do
            {:exception, exception_record} ->
              raise_exception(exception_record)
            success ->
              unquote(struct_module).to_elixir(success, unquote(reply_meta))
          end
      end

      def unquote(function_name)(unquote_splicing(arg_list)) do
        __MODULE__
        |> Process.whereis
        |> unquote(function_name)(unquote_splicing(arg_list))
      end
    end
  end

  defp build_client_functions(list_of_functions, thrift_meta, struct_module, overrides) do
    Enum.map(list_of_functions, &build_client_function(thrift_meta, struct_module, &1, overrides))
  end

  defmacro __before_compile__(env) do
    overrides = Riffed.Enumeration.get_overrides(env.module).functions
    opts = Module.get_attribute(env.module, :client_opts)
    struct_module = Module.get_attribute(env.module, :struct_module)
    thrift_client_module = Module.get_attribute(env.module, :thrift_module)
    functions = Module.get_attribute(env.module, :functions)


    thrift_metadata = extract(thrift_client_module, functions)
    num_retries = opts[:retries] || 0

    client_functions = build_client_functions(functions, thrift_metadata, struct_module, overrides)

    hostname = opts[:host]
    port = opts[:port]

    opts = opts
    |> Keyword.delete(:port)
    |> Keyword.delete(:host)
    |> Keyword.delete(:retries)

    if Module.get_attribute(env.module, :auto_import_structs) do
      struct_module = quote do
        defmodule unquote(struct_module) do
          use Riffed.Struct, unquote(Meta.structs_to_keyword(thrift_metadata))
          unquote_splicing(Riffed.Callbacks.reconstitute(env.module))
          unquote_splicing(Riffed.Enumeration.reconstitute(env.module))
        end
      end
    else
      struct_module = quote do
      end
    end

    quote do
      use GenServer
      unquote(struct_module)

      defmodule Client do
        defstruct client: nil, connect: nil

        def new(connect_fn) do
          {:ok, client} = connect_fn.()
          %Client{client: client, connect: connect_fn}
        end

        def reconnect(client=%Client{}) do
          {:ok, new_client} = client.connect.()
          %Client{client | client: new_client}
        end
      end

      def init(:ok) do
        {:ok, Client.new(&connect/0)}
      end

      def init({host, port}) do
        {:ok, Client.new(fn -> connect(host, port) end)}
      end

      def init(thrift_server) do
        {:ok, Client.new(fn -> {:ok, thrift_server} end)}
      end

      def start_link do
        GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
      end

      def start_link(thrift_client) do
        GenServer.start_link(__MODULE__, thrift_client, name: __MODULE__)
      end

      def start_link(host, port) do
        GenServer.start_link(__MODULE__, {host, port})
      end

      def handle_call({:disconnect, _args}, _parent, client=%Client{client: thrift_client}) do
        :thrift_client.close(thrift_client)
        {:reply, :ok, %{client | client: nil}}
      end

      def handle_call({:reconnect, _args}, _parent, client=%Client{client: nil}) do
        {:reply, :ok, Client.new(client.connect)}
      end

      def handle_call({:reconnect, _args}, _parent, client=%Client{client: thrift_client}) do
        :thrift_client.close(thrift_client)
        {:reply, :ok, Client.new(client.connect)}
      end

      unquote_splicing(client_functions)

      # the default no-op for functions that don't have exceptions.
      defp raise_exception(e) do
        e
      end

      def handle_call({call_name, args}, _parent, client) do
        {new_client, response} = call_thrift(client, call_name, args)
        {:reply, response, new_client}
      end

      defp call_thrift(client, call_name, args) do
        call_thrift(client, call_name, args, 0)
      end

      defp call_thrift(%Client{client: nil}, _, _, _) do
        {:error, :disconnected}
      end

      defp call_thrift(client, call_name, args, retry_count)
      when retry_count < unquote(num_retries) do
        {thrift_client, response} =
          try do
            :thrift_client.call(client.client, call_name, args)
          catch {new_client, exception} ->
              {new_client, exception}
          end

        new_client = %Client{client | client: thrift_client}
        case response do
          {:error, :closed} ->
            new_client = Client.reconnect(client)
            call_thrift(new_client, call_name, args, retry_count + 1)
          err = {:error, _} ->
            {new_client, err}
          exception = {:exception, exception_record} ->
            {:new_client, exception}
          {:ok, rsp} ->
            {new_client, rsp}
          other = {other, rsp} ->
            {new_client, other}
        end
      end

      defp call_thrift(client, call_name, args, retry_count) do
        {:error, :retries_exceeded}
      end

      defp connect do
        connect(unquote(hostname), unquote(port))
      end

      def connect(host, port) do
        :thrift_client_util.new(to_host(host),
                                port,
                                unquote(thrift_client_module),
                                unquote(opts))
      end

      def close do
        GenServer.call(__MODULE__, {:disconnect, []})
      end

      def close(pid) do
        GenServer.call(pid, {:disconnect, []})
      end

      def reconnect do
        GenServer.call(__MODULE__, {:reconnect, []})
      end

      defp to_host(hostname) when is_list(hostname) do
        hostname
      end

      defp to_host(hostname) when is_bitstring(hostname) do
        String.to_char_list(hostname)
      end
    end
  end

end
