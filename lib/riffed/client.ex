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

  defp build_client_function(thrift_metadata, struct_module, function_name, overrides) do
    function_meta = Meta.metadata_for_function(thrift_metadata, function_name)
    param_meta = function_meta[:params]
    reply_meta = function_meta[:reply] |> Riffed.Struct.to_riffed_type_spec

    reply_meta = Riffed.Enumeration.get_overridden_type(function_name, :return_type, overrides, reply_meta)

    arg_list = build_arg_list(param_meta)
    {:{}, _, list_args} = build_handler_tuple_args(param_meta)
    casts = build_casts(function_name, struct_module, param_meta, overrides, :to_erlang)

    quote do
      def unquote(function_name)(unquote_splicing(arg_list)) do
        unquote_splicing(casts)

        rv = GenServer.call(__MODULE__, {unquote(function_name), unquote(list_args)})
        unquote(struct_module).to_elixir(rv, unquote(reply_meta))
      end

      def unquote(function_name)(client_pid, unquote_splicing(arg_list))
        when is_pid(client_pid) do

          unquote_splicing(casts)

          rv = GenServer.call(client_pid, {unquote(function_name), unquote(list_args)})
          unquote(struct_module).to_elixir(rv, unquote(reply_meta))
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

    struct_module = if Module.get_attribute(env.module, :auto_import_structs) do
      quote do
        defmodule unquote(struct_module) do
          use Riffed.Struct, unquote(Meta.structs_to_keyword(thrift_metadata))
          unquote_splicing(Riffed.Callbacks.reconstitute(env.module))
          unquote_splicing(Riffed.Enumeration.reconstitute(env.module))
        end
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

      def start_link(host, port), do: start_link(host, port, [])

      def start_link(host, port, gen_server_opts) do
        GenServer.start_link(__MODULE__, {host, port}, gen_server_opts)
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

        {thrift_client, response}  = :thrift_client.call(client.client, call_name, args)
        new_client = %Client{client | client: thrift_client}
        case response do
          {:error, :closed} ->
            # close before we reconnect, otherwise we'll leak the socket's port.
            # it seems like the client should do this since it's handling the error
            # and is telling us that it's 'closed'. We've found out that we get many
            # sockets in ebadf state.
            :thrift_client.close(thrift_client)
            new_client = Client.reconnect(client)
            call_thrift(new_client, call_name, args, retry_count + 1)
          err = {:error, _} ->
            {new_client, err}
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
