defmodule RiftTutorial.Client do
  use Rift.Client,
  auto_import_structs: false,
  structs: RiftTutorial.Models,
  client_opts: [
    host: "localhost",
    port: 2112,
    retries: 3,
    framed: true],
  service: :tutorial_thrift,
  import: [:registerUser,
           :getUser,
           :getState,
           :setState]

  enumerize_function setState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
