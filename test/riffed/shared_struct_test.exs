defmodule SharedStructs do
  use Riffed.Struct,
  dest_modules: [account_types: AccountStructs],
  shared_service_types: [:AccountList],
  account_types: [:Account, :Preferences]

  defenum Status.Status do
    :inactive -> 1
    :active -> 2
    :core -> 3
  end

  enumerize_struct AccountList, status: Status.Status
end

defmodule SharingTests do
  use ExUnit.Case

  alias SharedStructs.AccountList
  alias SharedStructs.AccountStructs
  alias SharedStructs.Status

  setup do
    :ok
  end


  test "it should be able to convert imported structs to elixir" do
    created_at = 12277112
    updated_at = 27721771
    user_id = 1234

    account_list = {:AccountList, [{:Account, user_id, {:Preferences, user_id, false}, 'foo32@bar.com', created_at, updated_at}], 1}

    elixirized = SharedStructs.to_elixir(account_list, {:struct, {:shared_service_types, :AccountList}})

    assert %AccountList{} = elixirized
    %AccountList{accounts: [account]} = elixirized

    assert %AccountStructs.Account{userId: ^user_id,
                                   email: "foo32@bar.com",
                                   createdAt: ^created_at,
                                   updatedAt: ^updated_at} = account
    assert %AccountStructs.Preferences{userId: ^user_id,
                                       sendUpdates: false} = account.preferences
    inactive_status = Status.Status.inactive

    assert inactive_status = elixirized.status
  end

  test "it should be able to convert elixir structs into erlang records" do
    created_at = 12277112
    email = "foo32@bar.com"
    updated_at = 27721771
    user_id = 6553281

    account_list = %SharedStructs.AccountList{
      status: Status.Status.active,
      accounts: [%AccountStructs.Account{
                    createdAt: created_at,
                    email: email,
                    preferences: %AccountStructs.Preferences{sendUpdates: false,
                                                             userId: user_id},
                    updatedAt: updated_at, userId: user_id}]}
    erlangified = SharedStructs.to_erlang(account_list, nil)

    assert {:AccountList, [{:Account, ^user_id, {:Preferences, ^user_id, false}, ^email, ^created_at, ^updated_at}], 2} = erlangified
  end

end
