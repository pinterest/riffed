defmodule MultiClientTest do
  use ExUnit.Case

  defmodule ClientModels do
    use Riffed.Struct, account_types: [:Account, :Preferences]
  end

  defmodule AccountClient do
    use Riffed.Client, structs: ClientModels,
    client_opts: [host: "localhost",
                  port: 3112,
                  framed: true,
                  retries: 1,
                  socket_opts: [
                          recv_timeout: 3000,
                          keepalive: true]
                 ],
    service: :shared_service_thrift,
    import: [:getAccount]
  end

  test "allow multiple clients" do
    {:ok, echo} = EchoServer.start_link

    {:ok, pid1} = AccountClient.start_link(thrift_client: echo)
    {:ok, pid2} = AccountClient.start_link(thrift_client: echo)

    refute pid1 == pid2
  end
end
