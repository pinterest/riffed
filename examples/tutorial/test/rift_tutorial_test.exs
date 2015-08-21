defmodule RiftTutorialTest do
  use ExUnit.Case

  test "example client server test" do
    id = RiftTutorial.Client.registerUser("tupac")
    assert id == 0

    state = RiftTutorial.Client.getState(id)
    assert state == RiftTutorial.Models.UserState.active

    RiftTutorial.Client.setState(id, RiftTutorial.Models.UserState.banned)

    user = RiftTutorial.Client.getUser(id)
    assert user.username == "tupac"
    assert user.state == RiftTutorial.Models.UserState.banned
  end
end
