defmodule RiffedTutorial.Models do
  use Riffed.Struct, tutorial_types: [:User]

  defenum UserState do
    :active -> 0
    :inactive -> 1
    :banned -> 2
  end

  enumerize_struct User, state: UserState
end
