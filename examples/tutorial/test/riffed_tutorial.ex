defmodule RiffedTutorialTest do
  use ExUnit.Case

  test "example client server test" do
    id = RiffedTutorial.Client.registerUser("tupac")
    assert id == 0

    state = RiffedTutorial.Client.getState(id)
    assert state == RiffedTutorial.Models.UserState.active

    RiffedTutorial.Client.setState(id, RiffedTutorial.Models.UserState.banned)

    user = RiffedTutorial.Client.getUser(id)
    assert user.username == "tupac"
    assert user.state == RiffedTutorial.Models.UserState.banned
  end
end
