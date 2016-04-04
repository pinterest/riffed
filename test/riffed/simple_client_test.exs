defmodule SimpleClientTest do
  use ExUnit.Case
  import Mock

  defmodule SimpleClientEchoServer do
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
      {:reply, {:ok, args}, req}
    end

    def handle_call(:get_last_args, _parent, state) do
      {:reply, state, state}
    end
  end

  defmodule Client do
    use Riffed.SimpleClient,
      structs: SimpleClientModels,
      client: [
        :thrift_reconnecting_client,
        :start_link,
        'localhost',          # Host
        2112,                 # Port
        :server_thrift,       # ThriftSvc
        [framed: true],       # ThriftOpts
        100,                  # ReconnMin
        3_000,                # ReconnMax
      ],
      retry_delays: {100},
      service: :server_thrift,
      import: [
        :config,
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
        :functionWithoutNumberedArgs,
        :testException,
        :testMultiException,
      ]

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end

    enumerize_function getState(ActivityState), returns: ActivityState
    enumerize_function setUserState(_, ActivityState)
    enumerize_function getTranslatedState(ActivityState),
      returns: ActivityState
    enumerize_function echoState(ActivityState), returns: ActivityState
    enumerize_function echoActivityStateList({:list, ActivityState}),
      returns: {:list, ActivityState}
    enumerize_function getUserStates(_),
      returns: {:map, {:string, ActivityState}}
    enumerize_function getAllStates, returns: {:set, ActivityState}

    enumerize_struct User, state: ActivityState

    callback(:after_to_elixir, user=%LoudUser{}) do
      %SimpleClientModels.LoudUser{
        user |
        firstName: String.upcase(user.firstName),
        lastName: String.upcase(user.lastName)}
    end

    callback(:after_to_erlang, {:LoudUser, first_name, last_name}) do
      {:LoudUser, String.downcase(first_name), String.downcase(last_name)}
    end
  end

  setup do
    {:ok, pid} = SimpleClientEchoServer.start_link
    with_mock :thrift_reconnecting_client, [
      start_link: fn(_, _, _, _, _, _) -> {:ok, pid} end] do
      {:ok, ^pid} = Client.start_link(
        :thrift_reconnecting_client, :start_link, [
          'localhost',          # Host
          2112,                 # Port
          :server_thrift,       # ThriftSvc
          [framed: true],       # ThriftOpts
          100,                  # ReconnMin
          3_000,                # ReconnMax
        ]
      )
    end
    on_exit fn -> Utils.ensure_pid_stopped(pid) end
    Process.put(:simple_client_pid, pid)
    {:ok, pid: pid}
  end

  def user_struct do
    SimpleClientModels.User.new(
      firstName: "Foobie",
      lastName: "Barson",
      state: SimpleClientModels.ActivityState.active)
  end

  def user_tuple do
    {:User, "Foobie", "Barson", 1}
  end

  def config_request_struct do
    SimpleClientModels.ConfigRequest.new(
      template: "foo/bar",
      requestCount: 32,
      user: user_struct)
  end

  def respond_with(response) do
    fn(_client, fn_name, args) ->
      SimpleClientEchoServer.set_args({fn_name, args})
      {:ok, response}
    end
  end

  def exception_with(ex) do
    fn(_client, fn_name, args) ->
      SimpleClientEchoServer.set_args({fn_name, args})
      {:exception, ex}
    end
  end

  test "it should convert nested structs into erlang" do
    converted = SimpleClientModels.to_erlang(
      config_request_struct, {:struct, {:models, :ConfigRequest}})
    assert converted == {
      :ConfigRequest, "foo/bar", 32, {:User, "Foobie", "Barson", 1}}
  end

  test_with_mock "it should convert structs into their correct types",
  :thrift_reconnecting_client,
  [call: respond_with({:ConfigResponse, "foo/bar", 3, 32})] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.config(pid, config_request_struct, 3)
    assert response == SimpleClientModels.ConfigResponse.new(
      template: "foo/bar", requestCount: 3, per: 32)
    assert SimpleClientEchoServer.last_call == {:config, [
      {:ConfigRequest, "foo/bar", 32, {:User, "Foobie", "Barson", 1}}, 3]}
  end

  test_with_mock "it should convert structs in dicts",
  :thrift_reconnecting_client,
  [call: respond_with(:dict.from_list([{"foobar", user_tuple}]))] do
    pid = Process.get(:simple_client_pid)
    dict_arg = Enum.into([{"foobar", user_struct}], HashDict.new)
    {:ok, response} = Client.dictUserFun(pid, dict_arg)
    assert response == dict_arg
    assert SimpleClientEchoServer.last_call == {
      :dictUserFun, [:dict.from_list([{"foobar", user_tuple}])]}
  end

  test_with_mock "it should convert structs in sets",
  :thrift_reconnecting_client,
  [call: respond_with(:sets.from_list([user_tuple]))] do
    pid = Process.get(:simple_client_pid)
    set_arg = Enum.into([user_struct], HashSet.new)
    {:ok, response} = Client.setUserFun(pid, set_arg)
    assert response == set_arg
    {call_name, [set_arg]} = SimpleClientEchoServer.last_call
    assert call_name == :setUserFun
    assert set_arg == :sets.from_list([{:User, "Foobie", "Barson", 1}])
  end

  test_with_mock "it should convert enums in args",
  :thrift_reconnecting_client,
  [call: respond_with(3)] do
    pid = Process.get(:simple_client_pid)
    user_state = SimpleClientModels.ActivityState.inactive
    {:ok, response} = Client.getState(pid, user_state)
    assert response == SimpleClientModels.ActivityState.banned
    {call_name, [state]} = SimpleClientEchoServer.last_call
    assert call_name == :getState
    assert state == SimpleClientModels.ActivityState.inactive.value
  end

  test_with_mock "it should convert enums returned by client functions",
  :thrift_reconnecting_client,
  [call: respond_with(2)] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.getTranslatedState(
      pid, SimpleClientModels.ActivityState.banned)
    assert response == SimpleClientModels.ActivityState.inactive
    assert SimpleClientEchoServer.last_call == {:getTranslatedState, [3]}
  end

  test_with_mock "it shold convert enums in args and return values",
  :thrift_reconnecting_client,
  [call: fn(_client, _name, args) ->
     SimpleClientEchoServer.set_args(args)
     {:ok, 3}
   end] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.echoState(
      pid, SimpleClientModels.ActivityState.active)
    assert response == SimpleClientModels.ActivityState.banned
    [last_call] = SimpleClientEchoServer.last_call
    assert last_call == SimpleClientModels.ActivityState.active.value
  end

  test_with_mock "it should use callbacks to convert things to elixir",
  :thrift_reconnecting_client,
  [call: fn(_, _, _) -> {:ok, {:LoudUser, "stinky", "stinkman"}} end] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.getLoudUser(pid)
    assert response == SimpleClientModels.LoudUser.new(
      firstName: "STINKY", lastName: "STINKMAN")
  end

  test_with_mock "it should use callbacks to convert things to erlang",
  :thrift_reconnecting_client,
  [call: &SimpleClientEchoServer.call/3] do
    pid = Process.get(:simple_client_pid)
    Client.setLoudUser(pid, SimpleClientModels.LoudUser.new(
      firstName: "STINKY", lastName: "STINKMAN"))
    {call_name, [user_tuple]} = SimpleClientEchoServer.last_call
    assert call_name == :setLoudUser
    assert user_tuple == {:LoudUser, "stinky", "stinkman"}
  end

  test_with_mock "it should convert enums in lists",
  :thrift_reconnecting_client,
  [call: respond_with([3, 2, 1])] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.echoActivityStateList(
      pid, [SimpleClientModels.ActivityState.active])
    assert response == [
      SimpleClientModels.ActivityState.banned,
      SimpleClientModels.ActivityState.inactive,
      SimpleClientModels.ActivityState.active]
   end

  test_with_mock "it should convert enums in maps",
  :thrift_reconnecting_client,
  [call: respond_with(:dict.from_list([{"foobar", 3}, {"barfoo", 2}]))] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.getUserStates(pid, ["foobar", "barfoo"])
    assert response["foobar"] == SimpleClientModels.ActivityState.banned
    assert response["barfoo"] == SimpleClientModels.ActivityState.inactive
  end

  test_with_mock "it should convert enums in sets",
  :thrift_reconnecting_client,
  [call: respond_with(:sets.from_list([3, 2]))] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.getAllStates(pid)
    assert response == Enum.into(
      [SimpleClientModels.ActivityState.banned,
       SimpleClientModels.ActivityState.inactive],
      HashSet.new)
  end

  test_with_mock "it should convert things in response data structures",
  :thrift_reconnecting_client,
  [call: respond_with({
    :ResponseWithMap, :dict.from_list([{1234, user_tuple}])})] do

    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.getUsers(pid, 1234)
    user_dict = Enum.into([{1234, user_struct}], HashDict.new)
    assert response == SimpleClientModels.ResponseWithMap.new(users: user_dict)
  end

  test_with_mock "it should handle functions defined without argument numbers",
  :thrift_reconnecting_client,
  [call: respond_with(1234)] do
    pid = Process.get(:simple_client_pid)
    {:ok, response} = Client.functionWithoutNumberedArgs(pid, user_struct, 23)
    assert response == 1234
    assert SimpleClientEchoServer.last_call == {
      :functionWithoutNumberedArgs, [user_tuple, 23]}
  end

  test_with_mock "it should return exception",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception, 1001, "Xception"})] do
    pid = Process.get(:simple_client_pid)
    {:exception, ex} = Client.testException(pid, "Xception")
    assert ex == {:Xception, 1001, "Xception"}
    assert SimpleClientEchoServer.last_call == {
      :testException, ["Xception"]}
  end

  test_with_mock "it should raise exception",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception, 1001, "Xception"})] do
    pid = Process.get(:simple_client_pid)
    try do
      Client.testException!(pid, "Xception")
    catch
      :throw, {:exception, ex = %SimpleClientModels.Xception{}} ->
        assert ex == SimpleClientModels.Xception.new(
          errorCode: 1001, message: "Xception")
    end
    assert SimpleClientEchoServer.last_call == {
      :testException, ["Xception"]}
  end

  test_with_mock "it should return exception case 1",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception, 1001, "Xception"})] do
    pid = Process.get(:simple_client_pid)
    {:exception, ex} = Client.testMultiException(pid, "Xception", "Message")
    assert ex == {:Xception, 1001, "Xception"}
    assert SimpleClientEchoServer.last_call == {
      :testMultiException, ["Xception", "Message"]}
  end


  test_with_mock "it should return exception case 2",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception2, 2002, {
    :Xtruct, "Xception2", nil, nil, nil}})] do

    pid = Process.get(:simple_client_pid)
    {:exception, ex} = Client.testMultiException(pid, "Xception2", "Message")
    assert ex == {:Xception2, 2002, {
      :Xtruct, "Xception2", nil, nil, nil}}
    assert SimpleClientEchoServer.last_call == {
      :testMultiException, ["Xception2", "Message"]}
  end

  test_with_mock "it should raise exception case 1",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception, 1001, "Xception"})] do
    pid = Process.get(:simple_client_pid)
    try do
      Client.testMultiException!(pid, "Xception", "Message")
    catch
      :throw, {:exception, ex = %SimpleClientModels.Xception{}} ->
        assert ex == SimpleClientModels.Xception.new(
          errorCode: 1001, message: "Xception")
      :throw, {:exception, ex = %SimpleClientModels.Xception2{}} ->
        assert false
    end
    assert SimpleClientEchoServer.last_call == {
      :testMultiException, ["Xception", "Message"]}
  end

  test_with_mock "it should raise exception case 2",
  :thrift_reconnecting_client,
  [call: exception_with({:Xception2, 2002, {
    :Xtruct, "Xception2", nil, nil, nil}})] do

    pid = Process.get(:simple_client_pid)
    try do
      Client.testMultiException!(pid, "Xception2", "Message")
    catch
      :throw, {:exception, ex = %SimpleClientModels.Xception{}} ->
        assert false
      :throw, {:exception, ex = %SimpleClientModels.Xception2{}} ->
        assert ex == SimpleClientModels.Xception2.new(
          errorCode: 2002, struct_thing: SimpleClientModels.Xtruct.new(
            string_thing: "Xception2", byte_thing: nil,
            i32_thing: nil, i64_thing: nil))
    end
    assert SimpleClientEchoServer.last_call == {
      :testMultiException, ["Xception2", "Message"]}
  end
end
