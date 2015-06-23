defmodule SharedTests do
  use ExUnit.Case

  defmodule AccountModels do
    use Rift.Struct, account_types: [:Preferences, :Account]
  end

  defmodule PrefServer do
    use Rift.Server, service: :shared_service_thrift,
    auto_import_structs: false,
    structs: AccountModels,
    functions: [
            getPreferences: &SharedTests.Handler.get_preferences/1,
        ],
    server: {:thrift_socket_server,
             port: 2113,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }
  end

  defmodule AccountServer do
    use Rift.Server, service: :shared_service_thrift,
    auto_import_structs: false,
    structs: AccountModels,
    functions: [
            getAccount: &SharedTests.Handler.get_account/1
        ],
    server: {:thrift_socket_server,
             port: 2114,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }
  end

  defmodule Factory do
    def preferences(user_id) do
      AccountModels.Preferences.new(userId: user_id, sendUpdates: true)
    end

    def account(user_id) do
      AccountModels.Account.new(userId: user_id,
                                preferences: preferences(user_id),
                                email: "foo@bar.com",
                                createdAt: 12345,
                                updatedAt: 67890)
    end
  end

  defmodule Handler do
    def get_preferences(user_id) do
      Factory.preferences(user_id)
    end

    def get_account(user_id) do
      Factory.account(user_id)
    end
  end

  test "retrieving prefs should work" do
    {:reply, prefs} = PrefServer.handle_function(:getPreferences, {1234})
    assert {:Preferences, 1234, true} == prefs
  end

  test "retrieving an account should work" do
    {:reply, account} = AccountServer.handle_function(:getAccount, {1234})
    prefs = {:Preferences, 1234, true}
    assert {:Account, 1234, prefs, "foo@bar.com", 12345, 67890} == account
  end

end
