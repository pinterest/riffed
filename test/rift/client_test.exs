defmodule ClientTest do
  use ExUnit.Case
  import Mock

  defmodule Client do
    use Rift.Client, structs: Models,
    client_opts: [host: "localhost",
                  port: 2112,
                  framed: true,
                  retries: 1,
                  socket_opts: [
                          recv_timeout: 3000,
                          keepalive: true]
                 ],
    service: :server_thrift,
    import: [:config,
             :setUserState,
             :dictFun,
             :dictUserFun,
             :setUserFun,
             :getState,
             :getTranslatedState,
             :getLoudUser,
             :setLoudUser,
             :echoState
            ]

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end

    enumerize_function setUserState(_, ActivityState)
    enumerize_function getTranslatedState(_), returns: ActivityState
    enumerize_function echoState(ActivityState), returns: ActivityState

    enumerize_struct User, state: ActivityState

    callback(:after_to_elixir, user=%LoudUser{}) do

      %Models.LoudUser{user |
                       firstName: String.upcase(user.firstName),
                       lastName: String.upcase(user.lastName)}
    end

    callback(:after_to_erlang, {:LoudUser, first_name, last_name}) do
      downcase = fn(l) ->
        l |> List.to_string |> String.downcase |> String.to_char_list
      end
      {:LoudUser, downcase.(first_name), downcase.(last_name)}
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

    def set_args(args) do
      GenServer.call(__MODULE__, {:set_args, args})
    end

    def handle_call({:set_args, args}, _parent, _state) do
      {:reply, args, args}
    end

    def handle_call(req={_call_name, args}, _parent, _state) do
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
    Models.User.new(firstName: "Foobie",
                    lastName: "Barson",
                    state: Models.ActivityState.active)
  end

  def config_request_struct do
    Models.ConfigRequest.new(
      template: "foo/bar",
      requestCount: 32,
      user: user_struct)
  end

  test "it should convert nested structs into erlang" do
    converted = Models.to_erlang(config_request_struct)
    assert {:ConfigRequest, 'foo/bar', 32, {:User, 'Foobie', 'Barson', 1}} == converted
  end

  test_with_mock "it should convert structs into their correct types", :thrift_client,
  [call: &EchoServer.call/3] do
    [request, num] = Client.config(config_request_struct, 3)

    assert config_request_struct == request
    assert 3 == num
    assert {:config, [{:ConfigRequest, 'foo/bar', 32, {:User, 'Foobie', 'Barson', 1}}, 3]} == EchoServer.last_call
  end

  test_with_mock "it should convert structs in dicts", :thrift_client,
  [call: &EchoServer.call/3] do
    dict_arg = Enum.into([{"foobar", user_struct}], HashDict.new)

    [response] = Client.dictUserFun(dict_arg)

    assert dict_arg == response
    expected = {:dictUserFun, [:dict.from_list([{"foobar", {:User, 'Foobie', 'Barson', 1}}])]}
    assert expected == EchoServer.last_call
  end

  test_with_mock "it should convert structs in sets", :thrift_client,
  [call: &EchoServer.call/3] do
    set_arg = Enum.into([user_struct], HashSet.new)

    [response] = Client.setUserFun(set_arg)

    assert set_arg == response
    {call_name, [set_arg]} = EchoServer.last_call
    assert call_name == :setUserFun
    assert set_arg == :sets.from_list([{:User, 'Foobie', 'Barson', 1}])
  end

  test_with_mock "it should convert enums in args", :thrift_client,
  [call: &EchoServer.call/3] do
    user_state = Models.ActivityState.inactive

    [response] = Client.getState(user_state)
    assert response == Models.ActivityState.inactive

    {call_name, [state]} = EchoServer.last_call

    assert call_name == :getState
    Models.ActivityState.inactive == state
  end

  test_with_mock "it should convert enums returned by client functions", :thrift_client,
  [call: fn(client, _, _) -> {client, {:ok, 3}} end] do
    response = Client.getTranslatedState(3)
    assert response == Models.ActivityState.banned
  end

  test_with_mock "it shold convert enums in args and return values", :thrift_client,
  [call: fn(client, _name, args) ->
     EchoServer.set_args(args)
     {client, {:ok, 3}}
   end] do

    response = Client.echoState(Models.ActivityState.active)
    assert response == Models.ActivityState.banned
    [last_call] = EchoServer.last_call
    assert Models.ActivityState.active.value == last_call
  end

  test_with_mock "it should use callbacks to convert things to elixir", :thrift_client,
  [call: fn(client, _, _) -> {client, {:ok, {:LoudUser, 'stinky', 'stinkman'}}} end] do
    response = Client.getLoudUser()
    assert response == Models.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN")
  end

  test_with_mock "it should use callbacks to convert things to erlang", :thrift_client,
  [call: &EchoServer.call/3] do

    response = Client.setLoudUser(Models.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN"))
    {call_name, [user_tuple]} = EchoServer.last_call

    assert call_name == :setLoudUser
    assert {:LoudUser, 'stinky', 'stinkman'} == user_tuple
  end
end
