defmodule RiftTutorial.Models do
  use Rift.Struct, tutorial_types: [:User]

  defenum UserState do
    :active -> 0
    :inactive -> 1
    :banned -> 2
  end

  enumerize_struct User, state: UserState
end
