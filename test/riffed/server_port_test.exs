defmodule ServerPortTest do
  use ExUnit.Case, async: false

  defmodule Server do
    use Riffed.Server,
    service: :server_thrift,
    structs: __MODULE__.Model,
    auto_build_structs: true,
    functions: [
      getLoudUser: &ServerPortTest.Handler.get_loud_user/0,
    ],
    server: {:thrift_socket_server,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }
  end

  defmodule Handler do
    def get_loud_user, do: Server.Model.LoudUser.new
  end

  defmodule Client do
    use Riffed.Client,
    service: :server_thrift,
    auto_build_structs: true,
    structs: __MODULE__.Model,
    client_opts: [framed: true,
                  retries: 1,
                 ],
     import: [:getLoudUser]
  end

  test "Set server port at runtime" do
    port = 2113
    Server.start_link(port: port)
    Client.start_link("localhost", port, name: Client)

    %Client.Model.LoudUser{} = Client.getLoudUser
  end

end
