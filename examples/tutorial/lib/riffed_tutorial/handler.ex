defmodule RiffedTutorial.Handler do
  use GenServer
  alias RiffedTutorial.Models

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge(opts, name: __MODULE__))
  end

  def init(:ok) do
    db = :ets.new(:users, [:public, :named_table, read_concurrency: true])
    {:ok, db}
  end

  def register_user(username) do
    id = :ets.info(:users, :size)
    new_user = Models.User.new(id: id, username: username)
    :ets.insert_new(:users, {id, new_user})
    id
  end

  def get_user(user_id) do
    case :ets.lookup(:users, user_id) do
      [{^user_id, user}] -> user
      [] -> :error
    end
  end

  def get_state(user_id) do
    user = get_user(user_id)
    user.state
  end

  def set_state(user_id, state) do
    user = get_user(user_id)
    new_user = %{user | state: state}
    :ets.insert(:users, {user_id, new_user})
    :ok
  end
end
