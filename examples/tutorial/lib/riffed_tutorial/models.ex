defmodule RiffedTutorial.Models do
  use Riffed.Struct, tutorial_types: :auto

  enumerize_struct User, state: UserState
end
