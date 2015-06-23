defmodule StructTest do
  use ExUnit.Case

  defmodule Structs do
    use Rift.Struct, struct_types: [
            :Inner,
            :Nested,
            :NeedsFixup,
            :ListContainer,
            :SetContainer,
            :StringToEnumContainer,
            :IntToEnumContainer,
            :EnumToStringContainer,
            :DeeplyNestedContainer,
            :ListWithMap
        ]

    defenum Time do
      :day -> 1
      :week -> 2
      :month -> 3
    end

    enumerize_struct NeedsFixup, time: Time
    enumerize_struct ListContainer, timeList: {:list, Time}
    enumerize_struct SetContainer, timeSet: {:set, Time}
    enumerize_struct StringToEnumContainer, nameToTimePeriod: {:map, {:string, Time}}
    enumerize_struct IntToEnumContainer, intToTimePeriod: {:map, {:i32, Time}}
    enumerize_struct EnumToStringContainer, timePeriodToName: {:map, {Time, :string}}
    enumerize_struct DeeplyNestedContainer, deeplyNested: {:list, {:list, {:list, Time}}}
    enumerize_struct ListWithMap, bonanza: {:list, {:list, {:map, {Time, :string}}}}
  end

  def to_erlang(what) do
    Structs.to_erlang(what, nil)
  end

  def to_erlang(what, spec) do
    Structs.to_erlang(what, spec)
  end

  def to_elixir(what, spec) do
    Structs.to_elixir(what, spec)
  end

  setup do
    {:ok, struct: Structs.Inner.new(name: "Stinkypants"),
     tuple: {:Inner, "Stinkypants"}}
  end

  test "You should be able to create a new struct" do
    resp = Structs.Inner.new
    refute is_nil(resp)
  end

  test "You should be able to initialize a struct with arguments" do

    resp = Structs.Inner.new(name: "Stinkypants")
    assert %Structs.Inner{name: "Stinkypants"} == resp
  end

  test "You should be able to turn a struct into a tuple", context do
    tuple = context[:struct] |> to_erlang
    assert context[:tuple] == tuple
  end

  test "You should be able to turn a tuple into a struct", context do
    assert context[:struct] == to_elixir({:Inner, "Stinkypants"}, {:struct, {:struct_types, :Inner}})
  end

  test "it should handle nested structs" do
    erlang = {:Nested, {:Inner, "stinkypants"}}
    req = to_elixir(erlang, {:struct, {:struct_types, :Nested}})
    assert Structs.Inner.new(name: "stinkypants") == req.inner
  end

  test "a list of tuples should turn into a list of structs", context do
    actual = [context[:tuple]] |> to_elixir({:list, {:struct, {:struct_types, :Inner}}})
    assert [context[:struct]] == actual
  end

  test "list of structs should turn itself into a list of tuples", context do
    actual = [context[:struct]] |> to_erlang({:list, {:struct, {:struct_types, :Inner}}})
    assert [context[:tuple]] == actual
  end

  test "a set of tuples should turn itself into a HashSet of tuples", context do
    actual = :sets.from_list([context[:tuple]]) |> to_elixir({:set, {:struct, {:struct_types, :Inner}}})
    assert Enum.into([context[:struct]], HashSet.new) == actual
  end

  test "a HashSet of structs should turn itself into a set of tuples", context do
    actual = Enum.into([context[:struct]], HashSet.new) |> to_erlang({:set, {:struct, {:struct_types, :Inner}}})
    assert :sets.from_list([context[:tuple]]) == actual
  end

  test "a dict of tuples should turn itself into a HashDict of structs", context do
    actual = :dict.from_list([{"foo", context[:tuple]}]) |> to_elixir({:map, {:string, {:struct, {:struct_types, :Inner}}}})
    assert Enum.into([{"foo", context[:struct]}], HashDict.new) == actual
  end

  test "a HashDict of structs should turn itself into a dict of tuples", context do
    actual = Enum.into([{"foo", context[:struct]}], HashDict.new) |> to_erlang({:map, {:string, {:struct, {:struct_types, :Inner}}}})
    assert :dict.from_list([{"foo", context[:tuple]}]) == actual
  end

  test "A bare enum can be converted into erlang" do
    erlang_time = Structs.Time.week |> to_erlang(nil)
    assert Structs.Time.week.value == erlang_time
  end

  test "Enums in tuples are correctly converted to elixir" do
    actual = {:NeedsFixup, "Foo", 2} |> to_elixir({:struct, {:struct_types, :NeedsFixup}})
    assert Structs.Time.week == actual.time
  end

  test "Enums in structs are properly converted into erlang" do
    {:NeedsFixup, "My Name", thrift_value} = Structs.NeedsFixup.new(
      name: "My Name",
      time: Structs.Time.week) |> to_erlang({:struct, {:struct_types, :NeedsFixup}})
    assert Structs.Time.week.value == thrift_value
  end

  test "Enums in a list in a tuple are converted into elixir" do
    container = {:ListContainer, [2, 1, 3]}
    elixir_container = container |> to_elixir({:struct, {:struct_types, :ListContainer}})
    assert [Structs.Time.week, Structs.Time.day, Structs.Time.month] == elixir_container.timeList
  end

  test "Enums in a list in a struct can be converted to erlang" do
    container = Structs.ListContainer.new(timeList: [Structs.Time.week, Structs.Time.day])
    erlang_tuple = container |> to_erlang({:struct, {:struct_types, :Containers}})
    assert {:ListContainer, [2, 1]} == erlang_tuple
  end

  test "Enums in sets in a tuple are converted to elixir" do
    container = {:SetContainer, :sets.from_list([1, 2])}
    elixir_struct = container |> to_elixir({:struct, {:struct_types, :SetContainer}})

    assert Enum.into([Structs.Time.day, Structs.Time.week], HashSet.new) == elixir_struct.timeSet
  end

  test "Enums in sets in a struct can be converted to erlang" do
    elixir = Structs.SetContainer.new(timeSet: Enum.into([Structs.Time.day], HashSet.new))
    erlang_tuple = to_erlang(elixir, {:struct, {:struct_types, :SetContainer}})

    assert {:SetContainer, :sets.from_list([1])} == erlang_tuple
  end

  test "Enums in maps in a tuple can be converted to elixir" do
    erlang_tuple = {:StringToEnumContainer, :dict.from_list([{"foo", 2}])}
    elixir_struct = erlang_tuple |> to_elixir({:struct, {:struct_types, :StringToEnumContainer}})

    assert Enum.into([{"foo", Structs.Time.week}], HashDict.new) == elixir_struct.nameToTimePeriod
  end

  test "Enums in maps in a struct can be converted into erlang" do
    elixir_struct = Structs.StringToEnumContainer.new(nameToTimePeriod: Enum.into([{"foo", Structs.Time.day}], HashDict.new))
    erlang_tuple = to_erlang(elixir_struct, {:struct, {:struct_types, :StringToEnumContainer}})

    assert {:StringToEnumContainer, :dict.from_list([{"foo", 1}])} == erlang_tuple
  end

  test "enums can be converted from erlang when both the keys and values are ints" do
    erlang_tuple = {:IntToEnumContainer, :dict.from_list([{1, 2}])}
    elixir_struct = erlang_tuple |> to_elixir({:struct, {:struct_types, :IntToEnumContainer}})

    assert Enum.into([{1, Structs.Time.week}], HashDict.new) == elixir_struct.intToTimePeriod
  end

  test "enums can be converted from elixir when both the keys and values are ints" do
    elixir_struct = Structs.IntToEnumContainer.new(
      intToTimePeriod: Enum.into([{1, Structs.Time.week}], HashDict.new))


    erlang_tuple = elixir_struct |> to_erlang({:struct, {:struct_types, :IntToEnumContainer}})

    assert {:IntToEnumContainer, :dict.from_list([{1, 2}])} == erlang_tuple
  end

  test "enums can be the keys of a thrift struct" do
    erlang_tuple = {:EnumToStringContainer, :dict.from_list([{2, "week"}])}

    elixir_struct = to_elixir(erlang_tuple, {:struct, {:struct_types, :EnumToStringContainer}})
    assert Enum.into([{Structs.Time.week, "week"}], HashDict.new) == elixir_struct.timePeriodToName
  end

  test "enums as keys can be converted into erlang" do
    elixir_struct = Structs.EnumToStringContainer.new(
      timePeriodToName: Enum.into([{Structs.Time.day, "day"}], HashDict.new))

    erlang_tuple = to_erlang(elixir_struct, nil)
    assert {:EnumToStringContainer, :dict.from_list([{1, "day"}])} == erlang_tuple
  end

  test "deeply nested enums in lists can be converted to elixir" do
    erlang_tuple = {:DeeplyNestedContainer, [[[1]]]}
    elixir_struct = to_elixir(erlang_tuple, {:struct, {:struct_types, :DeeplyNestedContainer}})

    assert elixir_struct.deeplyNested == [[[Structs.Time.day]]]
  end

  test "deeply nested enums in lists in elixir can be converted to erlang" do
    elixir_struct = Structs.DeeplyNestedContainer.new(deeplyNested: [[[Structs.Time.week]]])
    erlang_tuple = to_erlang(elixir_struct, nil)

    assert {:DeeplyNestedContainer, [[[2]]]} == erlang_tuple
  end

  test "Time.ordinals returns an ordered list of ordinals from the Time defenum" do
    assert Structs.Time.ordinals == [:day, :week, :month]
  end

  test "Time.values returns an ordered list of values in the Time defenum" do
    assert Structs.Time.values == [1, 2, 3]
  end

  test "Time.mappings returns a keyword list of ordinals and values in the Time defenum" do
    assert Structs.Time.mappings == [day: 1, week: 2, month: 3]
  end

  test "a really crazy nested erlang structure can be converted to elixir" do
    internal_dict = :dict.from_list([{2, "week"}])
    erlang_tuple = {:ListWithMap, [[internal_dict]]}
    elixir_struct = to_elixir(erlang_tuple, {:struct, {:struct_types, :ListWithMap}})

    [[map]] = elixir_struct.bonanza
    assert Enum.into([{Structs.Time.week, "week"}], HashDict.new) == map
  end

  test "a really crazy elixir structure can be turned into erlang" do
    dict = Enum.into([{Structs.Time.month, "month"}], HashDict.new)
    elixir_struct = Structs.ListWithMap.new(bonanza: [[dict]])

    erlang_tuple = to_erlang(elixir_struct, nil)
    assert {:ListWithMap, [[:dict.from_list([{3, "month"}])]]} == erlang_tuple
  end


end
