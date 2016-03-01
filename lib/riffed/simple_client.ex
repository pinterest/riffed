defmodule Riffed.SimpleClient do
  @moduledoc ~S"""
  Provides a simple client wrapper, that can specify underlying module.

  ## Usage
  The Erlang Thrift client implementation doesn't provide useful Elixir
  mappings, nor does it gracefully handle socket termination.
  Riffed's wrapper does, dutifully converting between Elixir and thrift for you.

      defmodule Client do
        use Riffed.SimpleClient,
          structs: Models,
          client: [
            :thrift_reconnecting_client,
            :start_link,
            'localhost',          # Host
            2112,                 # Port
            :my_library_thrift,   # ThriftSvc
            [framed: true],       # ThriftOpts
            100,                  # ReconnMin
            3_000,                # ReconnMax
          ],
          register: true,
          retry_delays: {100, 300, 1_000},
          service: :my_library_thrift,
          import: [
            :configure,
            :create,
            :update,
            :delete,
          ]

        defenum UserState do
          :active -> 1
          :inactive -> 2
          :banned -> 3
        end

        enumerize_struct(User, state: UserState)
      end

  In the above example, you can see that we've imported the functions
  `configure`, `create`, `update`, and `delete`.
  Riffed generates helper functions in the `Client` module
  that convert to and from Elixir. To use the client, simply invoke:

      Client.start_link

      Client.configure("config", 234)
      Client.create(Models.user.new(first_name: "Stinky", last_name: "Stinkman")
      Client.close

  The Elixir bitstrings will be automatically converted to erlang char lists
  when being sent to the thrift client, and char lists from the client will be
  automatically converted to bitstrings when returned *by* the thrift client.
  Riffed looks at your thrift definitions to find out when this should happen,
  so it's safe.
  """
  import Riffed.MacroHelpers
  import Riffed.ThriftMeta, only: [extract: 2]
  alias Riffed.ThriftMeta.Meta, as: Meta

  defmacro __using__(opts) do
    struct_module_name = opts[:structs]
    client = opts[:client]
    retry_delays = opts[:retry_delays]
    thrift_module = opts[:service]
    functions = opts[:import]
    auto_import_structs = Keyword.get(opts, :auto_import_structs, true)
    register = Keyword.get(opts, :register, true)

    quote do
      use Riffed.Callbacks
      use Riffed.Enumeration

      @struct_module unquote(struct_module_name)
      @client unquote(client)
      @register unquote(register)
      @retry_delays unquote(retry_delays)
      @thrift_module unquote(thrift_module)
      @functions unquote(functions)
      @auto_import_structs unquote(auto_import_structs)
      @before_compile Riffed.SimpleClient
    end
  end

  defp build_client_function(metadata, struct_module, func, overrides) do
    function_meta = Meta.metadata_for_function(metadata, func)
    param_meta = function_meta[:params]
    reply_meta = function_meta[:reply] |> Riffed.Struct.to_riffed_type_spec
    reply_meta = Riffed.Enumeration.get_overridden_type(
      func, :return_type, overrides, reply_meta)

    arg_list = build_arg_list(length(param_meta))
    {:{}, _, list_args} = build_handler_tuple_args(param_meta)
    casts = build_casts(func, struct_module, param_meta, overrides, :to_erlang)

    quote do
      def unquote(func)(unquote_splicing(arg_list)) do
        unquote(func)(__MODULE__, unquote_splicing(arg_list))
      end

      def unquote(func)(client, unquote_splicing(arg_list)) do
        unquote_splicing(casts)
        result = call_thrift(client, unquote(func), unquote(list_args), 0)
        case result do
          {:ok, reply} ->
            {:ok, unquote(struct_module).to_elixir(reply, unquote(reply_meta))}
          other ->
            other
        end
      end
    end
  end

  defp build_client_functions(functions, metadata, struct_module, overrides) do
    Enum.map(functions, &build_client_function(
      metadata, struct_module, &1, overrides))
  end

  defmacro __before_compile__(env) do
    overrides = Riffed.Enumeration.get_overrides(env.module).functions
    client = Module.get_attribute(env.module, :client)
    retry_delays = Module.get_attribute(env.module, :retry_delays)
    struct_module = Module.get_attribute(env.module, :struct_module)
    thrift_module = Module.get_attribute(env.module, :thrift_module)
    functions = Module.get_attribute(env.module, :functions)

    [client_module, client_function | client_args] = client
    metadata = extract(thrift_module, functions)
    num_retries = retry_delays && tuple_size(retry_delays) || 0

    client_functions = build_client_functions(
      functions, metadata, struct_module, overrides)

    if Module.get_attribute(env.module, :auto_import_structs) do
      struct_module = quote do
        defmodule unquote(struct_module) do
          use Riffed.Struct, unquote(Meta.structs_to_keyword(metadata))
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

      unquote_splicing(client_functions)

      def start_link do
        case Process.whereis(__MODULE__) do
          nil ->
            ret = unquote(client_module).unquote(client_function)(
              unquote_splicing(client_args))
            case ret do
              {:ok, pid} ->
                if @register do
                  Process.register(pid, __MODULE__)
                end
                {:ok, pid}
              other ->
                other
            end
          pid ->
            {:error, {:already_started, pid}}
        end
      end

      def start_link(module, function, args) do
        apply(module, function, args)
      end

      def stop do
        case Process.whereis(__MODULE__) do
          nil ->
            :ok
          pid ->
            :gen_server.stop(pid)
        end
      end

      def stop(pid) do
        :gen_server.stop(pid)
      end

      defp call_thrift(client, call_name, args, retry_count)
      when retry_count <= unquote(num_retries) do
        response = unquote(client_module).call(client, call_name, args)
        case response do
          {:error, :closed} ->
            retry_delay(client, call_name, args, retry_count)
          {:error, :econnaborted} ->
            retry_delay(client, call_name, args, retry_count)
          {:error, :noconn} ->
            retry_delay(client, call_name, args, retry_count)
          other ->
            other
        end
      end

      defp call_thrift(client, call_name, args, retry_count) do
        {:error, :retries_exceeded}
      end

      defp retry_delay(client, call_name, args, retry_count) do
        delay = get_delay(@retry_delays, retry_count)
        :timer.sleep(delay)
        call_thrift(client, call_name, args, retry_count + 1)
      end

      defp get_delay(nil, _index), do: 0
      defp get_delay({}, _index), do: 0
      defp get_delay(_delays, index) when index < 0, do: 0
      defp get_delay(delays, index)
      when tuple_size(delays) > index, do: elem(delays, index)
      defp get_delay(delays, _index), do: elem(delays, tuple_size(delays) - 1)

    end
  end
end
