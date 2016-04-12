enum TimePeriod {
  DAY,
  WEEK,
  MONTH,
  YEAR;
}

struct Inner {
  1: string name;
}

struct Nested {
  1: Inner inner;
}

struct NeedsFixup {
  1: string name,
  2: TimePeriod time;
}

struct ListContainer {
  1: list<TimePeriod> timeList;
}

struct SetContainer {
  1: set<TimePeriod> timeSet;
}

struct StringToEnumContainer {
  1: map<string, TimePeriod> nameToTimePeriod;
}

struct IntToEnumContainer {
  1: map<i32, TimePeriod> intToTimePeriod;
}

struct EnumToStringContainer {
  1: map<TimePeriod, string> timePeriodToName;
}

struct DeeplyNestedContainer {
  1: list<list<list<TimePeriod>>> deeplyNested;
}

struct ListWithMap {
  1: list<list<map<TimePeriod, string>>> bonanza;
}

struct DefaultInt {
  1: i32 value = 42;
}

struct DefaultString {
  1: string hello = "world";
}

struct DefaultSecondField {
  1: i32 id;
  2: string value = "Mike";
}

struct DefaultListInts {
  1: list<i32> values = [4, 6, 7, 5, 3, 0, 9];
}

struct DefaultListStrings {
  1: list<string> values = ["hello", "world"];
}

struct DefaultSetStrings {
  1: set<string> values = ["hello", "world"];
}

struct DefaultMap {
  1: map<string, i32> mappings = {"cats": 3, "dogs": 4};
}

struct DefaultDeepContainer {
  1: list<list<map<i32, string>>> values = [[{1: "a"}, {2: "b"}]];
}

exception StructException {
  1: string message,
  2: i32 code;
}

service Struct {
}
