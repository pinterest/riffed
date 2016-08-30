ExUnit.start(max_cases: 1)

defmodule Utils do

  def ensure_pid_stopped(name) when is_atom(name) do
    name
    |> Process.whereis
    |> ensure_pid_stopped
  end

  def ensure_pid_stopped(server_pid) when is_pid(server_pid) do
    ref = Process.monitor(server_pid)
    Process.exit(server_pid, :normal)
    receive do
      {:DOWN, ^ref, _, _, _} ->
        :ok
    after 1000 ->
        {:error, :timeout}
    end
  end

  def ensure_agent_stopped(module_name) do
    try do
      case Process.whereis(module_name) do
        pid when is_pid(pid) ->
          Agent.stop(pid)
          Utils.ensure_pid_stopped(pid)
        _ ->
          nil
      end
    catch :exit, _ ->
        nil
    end
  end
end

defmodule EchoServer do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def call(_client, name, args) do
    GenServer.call(__MODULE__, {name, args})
  end

  def last_call do
    GenServer.call(__MODULE__, :get_last_args)
  end

  def set_args(args) do
    GenServer.call(__MODULE__, {:set_args, args})
  end

  def handle_call({:set_args, args}, _parent, _state) do
    {:reply, args, args}
  end

  def handle_call(req={_call_name, args}, _parent, _state) do
    {:reply, {nil, {:ok, args}}, req}
  end

  def handle_call(:get_last_args, _parent, state) do
    {:reply, state, state}
  end
end
