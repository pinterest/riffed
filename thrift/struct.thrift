enum TimePeriod {
  DAY,
  WEEK,
  MONTH;
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

service Struct {
}