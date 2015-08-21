enum UserState {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: i64 id;
  2: string username,
  3: UserState state = UserState.ACTIVE;
}

service Tutorial {
  i64 registerUser(1: string username);
  User getUser(1: i64 userId);
  UserState getState(1: i64 userId);
  void setState(1: i64 userId, 2: UserState state);
}
