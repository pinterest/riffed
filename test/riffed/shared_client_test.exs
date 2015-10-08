defmodule SharedClientTest do
  use ExUnit.Case
  import Mock

  defmodule ClientModels do
    use Riffed.Struct, account_types: [:Account, :Preferences]
  end

  defmodule AccountClient do
    use Riffed.Client, structs: ClientModels,
    client_opts: [host: "localhost",
                  port: 3112,
                  framed: true,
                  retries: 1,
                  socket_opts: [
                          recv_timeout: 3000,
                          keepalive: true]
                 ],
    service: :shared_service_thrift,
    auto_import_structs: false,
    import: [:getAccount]
  end

  defmodule PrefClient do
    use Riffed.Client, structs: ClientModels,
    client_opts: [host: "localhost",
                  port: 3112,
                  framed: true,
                  retries: 1,
                  socket_opts: [
                          recv_timeout: 3000,
                          keepalive: true]
                 ],
    service: :shared_service_thrift,
    auto_import_structs: false,
    import: [:getPreferences]
  end

  defmodule Factory do
    def preferences(user_id) do
      ClientModels.Preferences.new(userId: user_id,
                                   sendUpdates: true)
    end

    def account(user_id) do
      ClientModels.Account.new(userId: user_id,
                               preferences: preferences(user_id),
                               email: "foo@bar.com",
                               createdAt: 12345,
                               updatedAt: 67890)
    end
  end

  def respond_with(response) do
    fn(client, fn_name, args) ->
      EchoServer.set_args({fn_name, args})
      {client, {:ok, response}}
    end
  end

  setup do
    {:ok, echo} = EchoServer.start_link

    AccountClient.start_link(echo)
    PrefClient.start_link(echo)
    :ok
  end


  test_with_mock "it should get preferences", :thrift_client,
  [call: respond_with({:Preferences, 1234, true})] do
    assert Factory.preferences(1234) == PrefClient.getPreferences(1234)
  end

  test_with_mock "it should get the account", :thrift_client,
  [call: respond_with({:Account, 1234, {:Preferences, 1234, true},
                       "foo@bar.com", 12345, 67890})] do
    assert Factory.account(1234) == AccountClient.getAccount(1234)
  end
end
