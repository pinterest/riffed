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

service Struct {
}