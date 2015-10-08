defmodule RiffedTutorial.Server do
  use Riffed.Server,
  auto_import_structs: false,
  service: :tutorial_thrift,
  structs: RiffedTutorial.Models,
  functions: [registerUser: &RiffedTutorial.Handler.register_user/1,
              getUser: &RiffedTutorial.Handler.get_user/1,
              getState: &RiffedTutorial.Handler.get_state/1,
              setState: &RiffedTutorial.Handler.set_state/2
  ],
  server: {:thrift_socket_server,
           port: 2112,
           framed: true,
           max: 10_000,
           socket_opts: [
             recv_timeout: 3000,
             keepalive: true]
          }

  enumerize_function setState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
