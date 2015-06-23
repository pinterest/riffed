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
             :echoState,
             :echoActivityStateList,
             :getUserStates,
             :getAllStates,
             :getUsers,
             :functionWithoutNumberedArgs
            ]

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end

    enumerize_function getState(ActivityState), returns: ActivityState
    enumerize_function setUserState(_, ActivityState)
    enumerize_function getTranslatedState(ActivityState), returns: ActivityState
    enumerize_function echoState(ActivityState), returns: ActivityState
    enumerize_function echoActivityStateList({:list, ActivityState}), returns: {:list, ActivityState}
    enumerize_function getUserStates(_), returns: {:map, {:string, ActivityState}}
    enumerize_function getAllStates(), returns: {:set, ActivityState}

    enumerize_struct User, state: ActivityState

    callback(:after_to_elixir, user=%LoudUser{}) do
      %Models.LoudUser{user |
                       firstName: String.upcase(user.firstName),
                       lastName: String.upcase(user.lastName)}
    end

    callback(:after_to_erlang, {:LoudUser, first_name, last_name}) do
      {:LoudUser, String.downcase(first_name), String.downcase(last_name)}
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

  def user_tuple do
    {:User, "Foobie", "Barson", 1}
  end

  def config_request_struct do
    Models.ConfigRequest.new(
      template: "foo/bar",
      requestCount: 32,
      user: user_struct)
  end

  def respond_with(response) do
    fn(client, fn_name, args) ->
      EchoServer.set_args({fn_name, args})
      {client, {:ok, response}}
    end
  end

  test "it should convert nested structs into erlang" do
    converted = Models.to_erlang(config_request_struct, {:struct, {:models, :ConfigRequest}})
    assert {:ConfigRequest, "foo/bar", 32, {:User, "Foobie", "Barson", 1}} == converted
  end

  test_with_mock "it should convert structs into their correct types", :thrift_client,
  [call: respond_with({:ConfigResponse, "foo/bar", 3, 32})] do

    response = Client.config(config_request_struct, 3)

    assert Models.ConfigResponse.new(template: "foo/bar", requestCount: 3, per: 32) == response
    assert {:config, [{:ConfigRequest, "foo/bar", 32, {:User, "Foobie", "Barson", 1}}, 3]} == EchoServer.last_call
  end

  test_with_mock "it should convert structs in dicts", :thrift_client,
  [call: respond_with(:dict.from_list([{"foobar", user_tuple}]))] do
    dict_arg = Enum.into([{"foobar", user_struct}], HashDict.new)

    response = Client.dictUserFun(dict_arg)

    assert dict_arg == response
    expected = {:dictUserFun, [:dict.from_list([{"foobar", user_tuple}])]}
    assert expected == EchoServer.last_call
  end

  test_with_mock "it should convert structs in sets", :thrift_client,
  [call: respond_with(:sets.from_list([user_tuple]))] do
    set_arg = Enum.into([user_struct], HashSet.new)

    response = Client.setUserFun(set_arg)

    assert set_arg == response
    {call_name, [set_arg]} = EchoServer.last_call
    assert call_name == :setUserFun
    assert set_arg == :sets.from_list([{:User, "Foobie", "Barson", 1}])
  end

  test_with_mock "it should convert enums in args", :thrift_client,
  [call: respond_with(3)] do
    user_state = Models.ActivityState.inactive

    response = Client.getState(user_state)
    assert response == Models.ActivityState.banned

    {call_name, [state]} = EchoServer.last_call

    assert call_name == :getState
    Models.ActivityState.inactive == state
  end

  test_with_mock "it should convert enums returned by client functions", :thrift_client,
  [call: respond_with(2)] do
    response = Client.getTranslatedState(Models.ActivityState.banned)
    assert response == Models.ActivityState.inactive
    assert {:getTranslatedState, [3]} == EchoServer.last_call
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
  [call: fn(client, _, _) -> {client, {:ok, {:LoudUser, "stinky", "stinkman"}}} end] do
    response = Client.getLoudUser()
    assert response == Models.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN")
  end

  test_with_mock "it should use callbacks to convert things to erlang", :thrift_client,
  [call: &EchoServer.call/3] do

    response = Client.setLoudUser(Models.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN"))
    {call_name, [user_tuple]} = EchoServer.last_call

    assert call_name == :setLoudUser
    assert {:LoudUser, "stinky", "stinkman"} == user_tuple
  end

  test_with_mock "it should convert enums in lists", :thrift_client,
  [call: respond_with([3, 2, 1])] do

    response = Client.echoActivityStateList([Models.ActivityState.active])
    assert [Models.ActivityState.banned, Models.ActivityState.inactive, Models.ActivityState.active] == response
   end

  test_with_mock "it should convert enums in maps", :thrift_client,
  [call: respond_with(:dict.from_list([{"foobar", 3}, {"barfoo", 2}]))] do

    response = Client.getUserStates(["foobar", "barfoo"])
    assert Models.ActivityState.banned == response["foobar"]
    assert Models.ActivityState.inactive == response["barfoo"]
  end

  test_with_mock "it should convert enums in sets", :thrift_client,
  [call: respond_with(:sets.from_list([3, 2]))] do

    response = Client.getAllStates()
    assert Enum.into([Models.ActivityState.banned,
                      Models.ActivityState.inactive], HashSet.new) == response
  end

  test_with_mock "it should convert things in response data structures", :thrift_client,
  [call: respond_with({:ResponseWithMap, :dict.from_list([{1234, user_tuple}])})] do

    response = Client.getUsers(1234)
    user_dict = Enum.into([{1234, user_struct}], HashDict.new)
    assert Models.ResponseWithMap.new(users: user_dict) == response
  end

  test_with_mock "it should handle functions defined without argument numbers", :thrift_client,
  [call: respond_with(1234)] do
    response = Client.functionWithoutNumberedArgs(user_struct, 23)
    last_call = EchoServer.last_call

    assert response == 1234
    assert {:functionWithoutNumberedArgs, [user_tuple, 23]}  == last_call
  end
end
