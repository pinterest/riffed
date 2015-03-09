defmodule StructTest do
  use ExUnit.Case

  defmodule Structs do
    use Rift.Struct, struct_types: [:Inner, :Nested]
  end

  test "You should be able to create a new struct" do
    resp = Structs.Inner.new
    refute is_nil(resp)
  end

  test "You should be able to initialize a struct with arguments" do
    resp = Structs.Inner.new(name: "Stinkypants")
    assert %Structs.Inner{name: "Stinkypants"} == resp
  end

  test "You should be able to turn a struct into a tuple" do
    tuple = Structs.Inner.new(name: "Stinkypants") |> Rift.Adapt.to_erlang
    assert {:Inner, "Stinkypants"} == tuple
  end

  test "You should be able to turn a tuple into a struct" do
    expected = Structs.Inner.new(name: "Stinkypants")
    assert expected == Rift.Adapt.to_elixir({:Inner, "Stinkypants"})
  end

  test "it should handle nested structs" do
    erlang = {:Nested, {:Inner, "stinkypants"}}
    req = Rift.Adapt.to_elixir(erlang)
    assert Structs.Inner.new(name: "stinkypants") == req.inner
  end

end
