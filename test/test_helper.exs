ExUnit.start()

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
