defmodule RiffedTutorial.SimpleClient do
  use Riffed.SimpleClient,
    auto_import_structs: false,
    structs: RiffedTutorial.Models,
    client: [
      :thrift_reconnecting_client,
      :start_link,
      'localhost',          # Host
      2112,                 # Port
      :tutorial_thrift,     # ThriftSvc
      [                     # ThriftOpts
        framed: true,
        recv_timeout: 3_000,
      ],
      100,                  # ReconnMin
      3_000,                # ReconnMax
    ],
    retry_delays: {100, 300, 1_000},
    service: :tutorial_thrift,
    import: [
      :registerUser,
      :getUser,
      :getState,
      :setState,
    ]

  enumerize_function setState(_, UserState)
  enumerize_function getState(_), returns: UserState
end
