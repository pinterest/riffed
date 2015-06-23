defmodule ServerTest do
  use ExUnit.Case

  defmodule Server do
    use Rift.Server, service: :server_thrift,
    structs: Data,
    auto_build_structs: true,
    functions: [config: &ServerTest.FakeHandler.config/2,
                dictFun: &ServerTest.FakeHandler.dict_fun/1,
                dictUserFun: &ServerTest.FakeHandler.dict_fun/1,
                setFun: &ServerTest.FakeHandler.set_fun/1,
                setUserFun: &ServerTest.FakeHandler.set_fun/1,
                listFun: &ServerTest.FakeHandler.list_fun/1,
                listUserFun: &ServerTest.FakeHandler.list_fun/1,
                getState: &ServerTest.FakeHandler.get_state/1,
                getTranslatedState: &ServerTest.FakeHandler.get_translated_state/1,
                getLoudUser: &ServerTest.FakeHandler.get_loud_user/0,
                setLoudUser: &ServerTest.FakeHandler.set_loud_user/1,
                getUserStates: &ServerTest.FakeHandler.get_user_states/1,
                getUsers: &ServerTest.FakeHandler.get_users/1,
                getAllStates: &ServerTest.FakeHandler.get_all_states/0,
                echoActivityStateList: &ServerTest.FakeHandler.echo_activity_state_list/1,
                getMapResponse: &ServerTest.FakeHandler.get_map_response/0,
                getListResponse: &ServerTest.FakeHandler.get_list_response/0,
                getSetResponse: &ServerTest.FakeHandler.get_set_response/0,
                getUserBoardResponse: &ServerTest.FakeHandler.get_user_board_response/0
               ],

    server: {:thrift_socket_server,
             port: 2112,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }

    defenum ActivityState do
      :active -> 1
      :inactive -> 2
      :banned -> 3
    end

    enumerize_struct User, state: ActivityState
    enumerize_function getTranslatedState(_), returns: ActivityState
    enumerize_function getState(ActivityState), returns: ActivityState
    enumerize_function getUserStates(_), returns: {:map, {:string, ActivityState}}
    enumerize_function getAllStates(), returns: {:set, ActivityState}
    enumerize_function echoActivityStateList({:list, ActivityState}), returns: {:list, ActivityState}

    callback(:after_to_elixir, loudUser=%Data.LoudUser{}) do
      %Data.LoudUser{loudUser |
                     firstName: String.upcase(loudUser.firstName),
                     lastName: String.upcase(loudUser.lastName)}
    end


    callback(:after_to_erlang, {:LoudUser, firstName, lastName}) do
      {:LoudUser, String.downcase(firstName), String.downcase(lastName)}
    end
  end

  defmodule FakeHandler do
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def args do
      Agent.get(__MODULE__, fn(args) -> args end)
    end

    def set_args(args) do
      Agent.update(__MODULE__, fn(_) -> args end)
      args
    end

    def config(req=%Data.ConfigRequest{}, timestamp) do
      FakeHandler.set_args({req, timestamp})
      Data.ConfigResponse.new(template: req.template,
                              requestCount: req.requestCount,
                              per: 1)
    end

    def dict_fun(dict=%HashDict{}) do
      FakeHandler.set_args(dict)
    end

    def set_fun(hash_set=%HashSet{}) do
      FakeHandler.set_args(hash_set)
    end

    def list_fun(l) when is_list(l) do
      FakeHandler.set_args(l)
    end

    def get_state(state=%Data.ActivityState{}) do
      FakeHandler.set_args(state)
      state
    end

    def get_translated_state(int_status) do
      FakeHandler.set_args(int_status)
      Data.ActivityState.value(int_status)
    end

    def get_loud_user do
      Data.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN")
    end

    def set_loud_user(user) do
      FakeHandler.set_args(user)
    end

    def get_user_states(usernames) do
      FakeHandler.set_args(usernames)
      Enum.into(usernames, HashDict.new, fn(name) -> {name, Data.ActivityState.active} end)
    end

    def get_users(_user_ids) do
      users = Enum.into([{12345, Data.User.new(firstName: "Stinky",
                                               lastName: "Stinkman",
                                               state: Data.ActivityState.active)}],
                        HashDict.new)
      Data.ResponseWithMap.new(users: users)
    end

    def get_all_states do
      [Data.ActivityState.active, Data.ActivityState.inactive, Data.ActivityState.banned]
      |> Enum.into(HashSet.new)
    end

    def echo_activity_state_list(states) do
      FakeHandler.set_args(states)
      states
    end

    def get_user_board(board_id) do
      user = Data.User.new(firstName: "Foobie",
                           lastName: "Barson",
                           state: Data.ActivityState.active)
      board = Data.Board.new(id: board_id,
                             userId: 1234,
                             title: "My Sweet Board",
                             pinIds: [1, 2, 3, 4, 5])
      Enum.into([{board_id, Data.UserBoardResponse.new(user: user, board: board)}],
                HashDict.new)
    end

    def get_map_response do
      Data.MapResponse.new(mapId: 12)
    end

    def get_list_response do
      Data.ListResponse.new(listId: 2221)
    end

    def get_set_response do
      Data.SetResponse.new(setId: 2381)
    end

    def get_user_board_response do
      Data.UserBoardResponse.new(user: Data.User.new(firstName: "Foobie",
                                                     lastName: "Barson",
                                                     state: Data.ActivityState.active),
                                 board: Data.Board.new(id: 1234,
                                                       userId: 5678,
                                                       title: "Sweet stuff",
                                                       pinIds: [6, 9, 32]))
    end
  end

  setup do
    FakeHandler.start_link
    :ok
  end

  def user_tuple do
    {:User, "Steve", "Cohen", 1}
  end

  test "it should convert structs to and from elixir" do
    request = {:ConfigRequest, "users/:me", 1000, user_tuple}

    {:reply, response} = Server.handle_function(:config, {request, 1000})

    expected_user = Data.User.new(firstName: "Steve",
                                  lastName: "Cohen",
                                  state: Data.ActivityState.active)
    expected_request = Data.ConfigRequest.new(template: "users/:me",
                                              requestCount: 1000,
                                              user: expected_user)

    {request, timestamp} = FakeHandler.args
    assert expected_request == request
    assert 1000 == timestamp
    assert {:ConfigResponse, "users/:me", 1000, 1} == response
  end

  test "dicts are properly converted" do
    param = :dict.from_list([{"one", 1}, {"two", 2}])

    {:reply, response} = Server.handle_function(:dictFun, {param})

    hash_dict = FakeHandler.args
    assert hash_dict["one"] == 1
    assert hash_dict["two"] == 2

    assert {:ok, 1} == :dict.find("one", response)
    assert {:ok, 2} == :dict.find("two", response)
  end

  test "dicts with structs are converted" do
    user_dict = :dict.from_list([{"steve", user_tuple}])

    {:reply, response} = Server.handle_function(:dictUserFun, {user_dict})

    dict_arg = FakeHandler.args
    expected_user = Data.User.new(firstName: "Steve",
                                  lastName: "Cohen",
                                  state: Data.ActivityState.active)
    assert expected_user == dict_arg["steve"]
    assert user_dict == response
  end

  test "sets of structs are converted" do
    user = Data.User.new(firstName: "Steve", lastName: "Cohen", state: Data.ActivityState.active)
    param = :sets.from_list([user_tuple])

    {:reply, response} = Server.handle_function(:setUserFun, {param})

    set_arg = FakeHandler.args

    assert HashSet.to_list(set_arg) == [user]
    assert :sets.from_list([{:User, "Steve", "Cohen", 1}]) == response
  end


  test "sets are converted properly" do
    set_data = ["hi", "guys", "there"]
    param = :sets.from_list(set_data)

    {:reply, response} = Server.handle_function(:setFun, {param})

    set_arg = FakeHandler.args
    assert Set.equal? Enum.into(["hi", "there", "guys"], HashSet.new), set_arg
    assert :sets.from_list(set_data) == response
  end

  test "lists are handled properly" do
    list_data = [1, 2, 3, 4]

    {:reply, response} = Server.handle_function(:listFun, {list_data})

    assert [1, 2, 3, 4] == FakeHandler.args
    assert [1, 2, 3, 4] == response
  end

  test "lists of structs are properly converted" do
    user_list = [{:User, "Steve", "Cohen", 1}]

    {:reply, response} = Server.handle_function(:listUserFun, {user_list})

    assert [Data.User.new(firstName: "Steve",
                          lastName: "Cohen",
                          state: Data.ActivityState.active)] == FakeHandler.args
    assert user_list == response
  end

  test "An int in arguments is converted to an enum" do

    Server.handle_function(:getState, {3})

    assert Data.ActivityState.banned == FakeHandler.args
  end

  test "An enum is converted when it's returned by the server's handler function" do
    {:reply, response} = Server.handle_function(:getTranslatedState, {2})

    assert 2 == FakeHandler.args
    assert response == 2
  end

  test "A callback can convert data from elixir to erlang" do
    {:reply, response} = Server.handle_function(:getLoudUser, {})
    assert {:LoudUser, "stinky", "stinkman"} == response
  end

  test "A callback can convert data from erlang do elixir" do
    Server.handle_function(:setLoudUser, {{:LoudUser, "stinky", "stinkman"}})
    assert Data.LoudUser.new(firstName: "STINKY", lastName: "STINKMAN") == FakeHandler.args
  end

  test "Enums in maps in return values are properly handled" do
    {:reply, response} = Server.handle_function(:getUserStates, {["stinky", "stinkman"]})
    assert :dict.from_list([{"stinky", 1}, {"stinkman", 1}]) == response
  end

  test "Maps with objects are handled properly" do
    {:reply, {:ResponseWithMap, user_dict}} = Server.handle_function(:getUsers, {[12345]})
    assert :dict.from_list([{12345, {:User, "Stinky", "Stinkman", 1}}]) == user_dict
  end

  test "A return value of a set with enums is converted properly" do
    {:reply, enum_set} = Server.handle_function(:getAllStates, {})
    assert :sets.from_list([1, 2, 3]) == enum_set
  end

  test "A return value of a list of enums is converted properly" do
    {:reply, int_list} = Server.handle_function(:echoActivityStateList, {[1, 2, 3]})
    assert [Data.ActivityState.active, Data.ActivityState.inactive, Data.ActivityState.banned] == FakeHandler.args
    assert [1, 2, 3] == int_list
  end

  test "It should import return types defined in maps" do
    # If this compiles, the test is successful. Previously we were not properly
    # searching maps, lists and sets for structs.
    Server.handle_function(:getMapResponse, {})
  end

  test "It should import return types defined in lists" do
    # If this compiles, the test is successful. Previously we were not properly
    # searching maps, lists and sets for structs.
    Server.handle_function(:getListResponse, {})
  end

  test "It should import return types defined in sets" do
    # If this compiles, the test is successful. Previously we were not properly
    # searching maps, lists and sets for structs.
    Server.handle_function(:getSetResponse, {})
  end

  test "It should import return types defined inside structures inside of maps" do
    # If this compiles, the test is successful. Previously we were not properly
    # searching maps, lists and sets for structs.
    Server.handle_function(:getUserBoardResponse, {})
  end

end
