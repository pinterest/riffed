defmodule IntegrationTest do
  use ExUnit.Case

  defmodule IntegServer do
    use Riffed.Server, service: :server_thrift,
    structs: IntegServer.Models,
    functions: [getUserStates: &IntegServer.Handlers.get_user_states/1,
                echoString: &IntegServer.Handlers.echo_string/1,
                callAndBlowUp: &IntegServer.Handlers.call_and_blow_up/2
               ],

    server: {
            :thrift_socket_server,
            port: 22831,
            framed: true,
            socket_opts: [recv_timeout: 1000]
        }

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end

    enumerize_function getUserStates(_), returns: {:map, {:string, ActivityState}}

    defmodule Handlers do
      def get_user_states(list_of_usernames) do
        list_of_usernames
        |> Enum.into(HashDict.new,
            fn(name) ->
              {name, IntegServer.Models.ActivityState.active}
            end)
      end

      def echo_string(input) do
        input
      end

      def call_and_blow_up(message, _) do
        raise IntegServer.Models.UsageException.new(message: message, code: 999)
      end
    end
  end

  defmodule ServerWithErrorHandler do
    use Riffed.Server, service: :error_handler_thrift,
    structs: ServerWithErrorHandler.Models,
    functions: [],
    server: {
            :thrift_socket_server,
            port: 11337,
            framed: true,
            socket_opts: [recv_timeout: 1000]
        },
    error_handler: &ServerWithErrorHandler.on_failure/2

    def on_failure(_, _) do
      File.write!("rift_error_test.log", "The client left us in the dust")
    end
  end

  defmodule EasyClient do
    use Riffed.Client,
    structs: EasyClient.Models,
    client_opts: [host: "localhost",
                  port: 22831,
                  framed: true,
                  retries: 3],
    service: :server_thrift,
    import: [:getUserStates, :echoString, :callAndBlowUp]
  end

  defmodule EnumerizedClient do
    use Riffed.Client,
    structs: EnumerizedClient.Models,
    client_opts: [host: "localhost",
                  port: 22831,
                  framed: true,
                  retries: 3],
    service: :server_thrift,
    import: [:getUserStates]

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end
    enumerize_function getUserStates(_), returns: {:map, {:string, ActivityState}}
  end

  defmodule HostAndPortClient do
    use Riffed.Client,
    structs: HostAndPortClient.Models,
    client_opts: [
            framed: true,
            retries: 3
        ],
    service: :server_thrift,
    import: [:getUserStates, :echoString]
  end

  defmodule ErrorHandlerClient do
    use Riffed.Client,
    structs: ErrorHandlerClient.Models,
    client_opts: [host: "localhost",
                  port: 11337,
                  framed: true,
                  retries: 3],
    service: :error_handler_thrift,
    import: []
  end

  setup do
    {:ok, integ_server_pid} = IntegServer.start_link
    {:ok, error_server_pid} = ServerWithErrorHandler.start_link

    on_exit fn ->
      Utils.ensure_pid_stopped(integ_server_pid)
      Utils.ensure_pid_stopped(error_server_pid)
    end

    :ok
  end

  test "The easy client should work" do
    EasyClient.start_link
    rsp = EasyClient.getUserStates!(["foo"])

    assert 1 == rsp["foo"]
  end

  test "The enumerized client should convert into structs" do
    EnumerizedClient.start_link

    assert {:ok, _} = EnumerizedClient.getUserStates(["foo"])
    response = EnumerizedClient.getUserStates!(["foo"])

    assert EnumerizedClient.Models.ActivityState.active == response["foo"]
  end

  test "The host and port client should work" do
    {:ok, client} = HostAndPortClient.start_link("localhost", 22831)

    assert {:ok, _} = HostAndPortClient.getUserStates(client, ["foo"])
    response = HostAndPortClient.getUserStates!(client, ["foo"])

    assert 1 == response["foo"]
  end

  test "unicode text should be supported" do
    EasyClient.start_link
    rsp = EasyClient.echoString!("マイケルさんはすごいですよ。")
    assert "マイケルさんはすごいですよ。" == rsp
  end

  test "Can attach own error handler for when client disconnects" do
    refute File.exists?("rift_error_test.log")
    {:ok, client} = ErrorHandlerClient.start_link
    ErrorHandlerClient.close(client)

    # Sleep for a bit while the server writes to file
    :timer.sleep(100)

    assert File.read!("rift_error_test.log") == "The client left us in the dust"
    File.rm! "rift_error_test.log"
  end

  test "Can reconnect client" do
    EasyClient.start_link
    EasyClient.reconnect
    rsp = EasyClient.getUserStates!(["foo"])
    assert 1 == rsp["foo"]
  end

  test "Disconnected client should return :disconnected if calls are made" do
    EasyClient.start_link
    EasyClient.close

    assert :disconnected == EasyClient.getUserStates!(["foo"])
  end

  test "Can reconnect client after disconnecting" do
    EasyClient.start_link
    EasyClient.close
    EasyClient.reconnect
    rsp = EasyClient.getUserStates!(["foo"])
    assert 1 == rsp["foo"]
  end

  test "Can send empty strings" do
    {:ok, client} = HostAndPortClient.start_link("localhost", 22831)

    assert nil == HostAndPortClient.echoString!(client, nil)
  end

  test "can handle exceptions" do
    EasyClient.start_link
    assert {:error, %EasyClient.Models.UsageException{}} = EasyClient.callAndBlowUp("foo", "bar")
    assert_raise EasyClient.Models.UsageException, fn ->
      EasyClient.callAndBlowUp!("foo", "bar")
    end
  end
end
