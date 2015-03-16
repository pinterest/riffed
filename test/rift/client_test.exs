defmodule ClientTest do
  use ExUnit.Case
  import Mock

  defmodule Client do
    use Rift.Client, structs: Models,
    client_opts: [host: "localhost",
                  port: 2112,
                  framed: true,
                  socket_opts: [
                          recv_timeout: 3000,
                          keepalive: true]
                  ],
    service: :server_thrift,
    import: [:config,
             :dictFun,
             :dictUserFun,
             :setUserFun,
             :getState
            ]

    callback(:after_to_elixir, user_state=%UserState{}) do
      new_status = case user_state.status do
                     1 -> :active
                     2 -> :inactive
                     3 -> :banned
                   end
      %Models.UserState{user_state | status: new_status}
    end

    callback(:after_to_erlang, user_status={:UserState, user, status}) do
      new_status = case status do
                     :active -> 1
                     :inactive -> 2
                     :banned -> 3
                   end
      {:UserState, user, new_status}
    end
  end

  defmodule EchoServer do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, nil, name: __MODULE__)
    end

    def call(_client, name, args) do
      GenServer.call(__MODULE__, {name, args})
    end

    def last_call do
      GenServer.call(__MODULE__, :get_last_args)
    end

    def handle_call(req={call_name, args}, _parent, _state) do
      {:reply, {nil, {:ok, args}}, req}
    end

    def handle_call(:get_last_args, _parent, state) do
      {:reply, state, state}
    end

  end

  setup do
    {:ok, echo} = EchoServer.start_link
    Client.start_link(echo)

    :ok
  end

  def user_struct do
    Models.User.new(firstName: "Foobie", lastName: "Barson")
  end

  def config_request_struct do
    Models.ConfigRequest.new(
      template: "foo/bar",
      requestCount: 32,
      user: user_struct)
  end

  test "it should convert nested structs into erlang" do
    converted = Models.to_erlang(config_request_struct)
    assert {:ConfigRequest, 'foo/bar', 32, {:User, 'Foobie', 'Barson'}} == converted
  end

  test_with_mock "it should convert structs into their correct types", :thrift_client,
  [call: &EchoServer.call/3] do
    [request, num] = Client.config(config_request_struct, 3)

    assert config_request_struct == request
    assert 3 == num
    assert {:config, [{:ConfigRequest, 'foo/bar', 32, {:User, 'Foobie', 'Barson'}}, 3]} == EchoServer.last_call
  end


  test_with_mock "it should convert structs in dicts", :thrift_client,
  [call: &EchoServer.call/3] do
    dict_arg = Enum.into([{"foobar", user_struct}], HashDict.new)

    [response] = Client.dictUserFun(dict_arg)

    assert dict_arg == response
    expected = {:dictUserFun, [:dict.from_list([{"foobar", {:User, 'Foobie', 'Barson'}}])]}
    assert expected == EchoServer.last_call
  end

  test_with_mock "it should convert structs in sets", :thrift_client,
  [call: &EchoServer.call/3] do
    set_arg = Enum.into([user_struct], HashSet.new)

    [response] = Client.setUserFun(set_arg)

    assert set_arg == response
    {call_name, [set_arg]} = EchoServer.last_call
    assert call_name == :setUserFun
    assert set_arg == :sets.from_list([{:User, 'Foobie', 'Barson'}])
  end

  test_with_mock "it should have callbacks that work", :thrift_client,
  [call: &EchoServer.call/3] do
    user_status = Models.UserState.new(user: user_struct, status: :active)

   [response] = Client.getState(user_status)
   assert response.status == :active
   {call_name, [state]} = EchoServer.last_call

   assert call_name == :getState
   {:UserState, user, status} = state
   assert status == 1
  end

end
