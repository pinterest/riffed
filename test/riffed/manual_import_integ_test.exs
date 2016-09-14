defmodule ManualImportIntegTest do
  use ExUnit.Case

  defmodule Structs do
    use Riffed.Struct,
    dest_modules: [structures_types: Shared,
                   server_types: Server
                  ],
    structures_types: :auto,
    server_types: :auto
  end

  defmodule Server do
    use Riffed.Server, service: :server_thrift,
    structs: Structs,
    auto_import_structs: false,
    functions: [callAndBlowUp: &Server.Handlers.call_and_blow_up/2],
    server: {:thrift_socket_server,
             port: 23832,
             framed: true,
             socket_opts: [recv_timeout: 1000]
            }

    defmodule Handlers do
      def call_and_blow_up(message, type) do
        alias Structs.Shared.ServerException
        alias Structs.Server.UsageException

        case type do
          "usage" ->
            raise UsageException.new(message: message)

          "server" ->
            raise ServerException.new(message: message)
        end
      end
    end
  end
  defmodule Client do
    use Riffed.Client, structs: Structs,
    auto_import_structs: false,
    client_opts: [host: "localhost",
                  port: 23832,
                  framed: true,
                  retries: 3],
    service: :server_thrift,
    import: [:callAndBlowUp]
  end

  setup do
    {:ok, server_pid} = Server.start_link
    {:ok, client_pid} = Client.start_link

    on_exit fn ->
      Utils.ensure_pid_stopped(server_pid)
      Utils.ensure_pid_stopped(client_pid)
    end
  end

  test "it should blow up with the proper exception" do
    alias Structs.Server.UsageException
    alias Structs.Shared.ServerException

    assert_raise UsageException, fn ->
      Client.callAndBlowUp("Hello", "usage")
      |> IO.inspect
    end

    assert_raise ServerException, fn ->
      Client.callAndBlowUp("Goodbye", "server")
    end

    # shouldn't blow up
    Client.callAndBlowUp("Don't blow up", "none")
  end
end
