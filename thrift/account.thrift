struct Preferences {
  1: i64 userId,
  2: bool sendUpdates;
}

struct Account {
  1: i32 userId,
  2: Preferences preferences,
  3: string email,
  4: i64 createdAt,
  5: i64 updatedAt;
}
