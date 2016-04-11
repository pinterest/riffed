defmodule RiffedTutorial.Client do
  use Riffed.Client,
  auto_import_structs: false,
  structs: RiffedTutorial.Models,
  client_opts: [
    host: "localhost",
    port: 2112,
    retries: 3,
    framed: true],
  service: :tutorial_thrift

  enumerize_function setState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
