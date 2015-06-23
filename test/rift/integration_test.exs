defmodule IntegrationTest do
  use ExUnit.Case

  defmodule IntegServer do
    use Rift.Server, service: :server_thrift,
    structs: IntegServer.Models,
    functions: [getUserStates: &IntegServer.Handlers.get_user_states/1,
                echoString: &IntegServer.Handlers.echo_string/1],
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
    end
  end

  defmodule EasyClient do
    use Rift.Client,
    structs: EasyClient.Models,
    client_opts: [host: "localhost",
                  port: 22831,
                  framed: true,
                  retries: 3],
    service: :server_thrift,
    import: [:getUserStates, :echoString]
  end

  defmodule EnumerizedClient do
    use Rift.Client,
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
    use Rift.Client,
    structs: HostAndPortClient.Models,
    client_opts: [
            framed: true,
            retries: 3
        ],
    service: :server_thrift,
    import: [:getUserStates]
  end

  setup do
    IntegServer.start_link
    :ok
  end

  test "The easy client should work" do
    EasyClient.start_link
    rsp = EasyClient.getUserStates(["foo"])
    assert 1 == rsp["foo"]
  end

  test "The enumerized client should convert into structs" do
    EnumerizedClient.start_link
    response = EnumerizedClient.getUserStates(["foo"])

    assert EnumerizedClient.Models.ActivityState.active == response["foo"]
  end

  test "The host and port client should work" do
    {:ok, client} = HostAndPortClient.start_link("localhost", 22831)
    response = HostAndPortClient.getUserStates(client, ["foo"])

    assert 1 == response["foo"]
  end

  test "unicode text should be supported" do
    EasyClient.start_link
    rsp = EasyClient.echoString("マイケルさんはすごいですよ。")
    assert "マイケルさんはすごいですよ。" == rsp
  end

end
