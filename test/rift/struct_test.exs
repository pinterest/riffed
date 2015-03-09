defmodule StructTest do
  use ExUnit.Case

  defmodule Structs do
    use Rift.Struct, struct_types: [:Inner, :Nested]
  end

  setup do
    {:ok, struct: Structs.Inner.new(name: "Stinkypants"),
     tuple: {:Inner, "Stinkypants"}}
  end

  test "You should be able to create a new struct" do
    resp = Structs.Inner.new
    refute is_nil(resp)
  end

  test "You should be able to initialize a struct with arguments", context do

    resp = Structs.Inner.new(name: "Stinkypants")
    assert %Structs.Inner{name: "Stinkypants"} == resp
  end

  test "You should be able to turn a struct into a tuple", context do
    tuple = context[:struct] |> Structs.to_erlang
    assert context[:tuple] == tuple
  end

  test "You should be able to turn a tuple into a struct", context do
    assert context[:struct] == Structs.to_elixir({:Inner, "Stinkypants"})
  end

  test "it should handle nested structs" do
    erlang = {:Nested, {:Inner, "stinkypants"}}
    req = Structs.to_elixir(erlang)
    assert Structs.Inner.new(name: "stinkypants") == req.inner
  end

  test "a list of tuples should turn into a list of structs", context do
    actual = [context[:tuple]] |> Structs.to_elixir
    assert [context[:struct]] == actual
  end

  test "list of structs should turn itself into a list of tuples", context do
    actual = [context[:struct]] |> Structs.to_erlang
    assert [context[:tuple]] == actual
  end

  test "a set of tuples should turn itself into a HashSet of tuples", context do
    actual = :sets.from_list([context[:tuple]]) |> Structs.to_elixir
    assert Enum.into([context[:struct]], HashSet.new) == actual
  end

  test "a HashSet of structs should turn itself into a set of tuples", context do
    actual = Enum.into([context[:struct]], HashSet.new) |> Structs.to_erlang
    assert :sets.from_list([context[:tuple]]) == actual
  end

  test "a dict of tuples should turn itself into a HashDict of structs", context do
    actual = :dict.from_list([{"foo", context[:tuple]}]) |> Structs.to_elixir
    assert Enum.into([{"foo", context[:struct]}], HashDict.new) == actual
  end

  test "a HashDict of structs should turn itself into a dict of tuples", context do
    actual = Enum.into([{"foo", context[:struct]}], HashDict.new) |> Structs.to_erlang
    assert :dict.from_list([{"foo", context[:tuple]}]) == actual
  end

end
