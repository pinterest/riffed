defmodule ServerTest do
  use ExUnit.Case

  defmodule Server do
    use Rift.Server, service: :server_thrift,
    structs: Data,
    functions: [config: &ServerTest.FakeHandler.config/2,
                dictFun: &ServerTest.FakeHandler.dict_fun/1,
                dictUserFun: &ServerTest.FakeHandler.dict_fun/1,
                setFun: &ServerTest.FakeHandler.set_fun/1,
                setUserFun: &ServerTest.FakeHandler.set_fun/1,
                listFun: &ServerTest.FakeHandler.list_fun/1,
                listUserFun: &ServerTest.FakeHandler.list_fun/1,
                getState: &ServerTest.FakeHandler.get_state/1
               ],

    server: {:thrift_socket_server,
             port: 2112,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }

    callback(:after_to_elixir, user_status=%Data.UserState{}) do
      status = case user_status.status do
                1 -> :active
                2 -> :inactive
                3 -> :banned
              end
      %Data.UserState{user_status | status: status}
    end

    callback(:after_to_erlang, {:UserState, user, state}) do
      new_state = case state do
                    :active -> 1
                    :inactive -> 2
                    :banned -> 3
                  end
      {:UserState, user, new_state}
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

    def get_state(user_state=%Data.UserState{}) do
      FakeHandler.set_args(user_state)
      user_state
    end
  end

  setup do
    FakeHandler.start_link
    :ok
  end

  test "it should convert structs to and from elixir" do
    request = {:ConfigRequest, "users/:me", 1000, {:User, 'Steve', 'Cohen'}}

    response = Server.handle_function(:config, {request, 1000})

    expected_user = Data.User.new(firstName: 'Steve', lastName: 'Cohen')
    expected_request = Data.ConfigRequest.new(template: "users/:me",
                                              requestCount: 1000,
                                              user: expected_user)

    {request, timestamp} = FakeHandler.args
    assert expected_request == request
    assert 1000 == timestamp
    assert {:ConfigResponse, "users/:me", 1000, 1} == response
  end

  test "dicts are properly converted" do
    param = :dict.from_list([{'one', 1}, {'two', 2}])

    response = Server.handle_function(:dictFun, {param})

    hash_dict = FakeHandler.args
    assert hash_dict['one'] == 1
    assert hash_dict['two'] == 2

    assert {:ok, 1} == :dict.find('one', response)
    assert {:ok, 2} == :dict.find('two', response)
  end

  test "dicts with structs are converted" do
    user_dict = :dict.from_list([{'steve', {:User, "Steve", "Cohen"}}])

    response = Server.handle_function(:dictUserFun, {user_dict})

    dict_arg = FakeHandler.args
    assert Data.User.new(firstName: "Steve", lastName: "Cohen") == dict_arg['steve']
    assert user_dict == response
  end

  test "sets of structs are converted" do
    user = Data.User.new(firstName: "Steve", lastName: "Cohen")
    param = :sets.from_list([{:User, "Steve", "Cohen"}])

    response = Server.handle_function(:setUserFun, {param})

    set_arg = FakeHandler.args

    assert HashSet.to_list(set_arg) == [user]
    assert :sets.from_list([{:User, "Steve", "Cohen"}]) == response
  end


  test "sets are converted properly" do
    set_data = ['hi', 'there', 'guys']
    param = :sets.from_list(set_data)

    response = Server.handle_function(:setFun, {param})

    set_arg = FakeHandler.args
    assert Enum.into(set_data, HashSet.new) == set_arg
    assert :sets.from_list(set_data) == response
  end

  test "lists are handled properly" do
    list_data = [1, 2, 3, 4]

    response = Server.handle_function(:listFun, {list_data})

    assert [1, 2, 3, 4] == FakeHandler.args
    assert [1, 2, 3, 4] == response
  end

  test "lists of structs are properly converted" do
    user_list = [{:User, "Steve", "Cohen"}]

    response = Server.handle_function(:listUserFun, {user_list})

    assert [Data.User.new(firstName: "Steve", lastName: "Cohen")] == FakeHandler.args
    assert user_list == response
  end

  test "A callback is called when data is serialized" do
    user_state = {:UserState, {:User, "Stinky", "Stinkman"}, 2}

    response = Server.handle_function(:getState, {user_state})

    assert :inactive == FakeHandler.args.status

    {:UserState, _user, state} = response
    assert state == 2
  end
end
