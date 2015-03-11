enum UserStatus {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: string firstName,
  2: string lastName;
}

struct ConfigRequest {
  1: string template,
  2: i32 requestCount,
  3: User user;
}

struct ConfigResponse {
  1: string template,
  2: i32 requestCount,
  3: i32 per;
}

struct UserState {
  1: User user,
  2: UserStatus status;
}

service Server {
  ConfigResponse config(1: ConfigRequest request, i32 timestamp);
  map<string, i32> dictFun(1: map<string, i32> dict);
  map<string, User> dictUserFun(1: map<string, User> dict);
  set<string> setFun(1: set<string> mySet);
  set<User> setUserFun(1: set<User> mySet);
  list<i32> listFun(1: list<i32> numbers);
  list<User> listUserFun(1: list<User> users);
  UserState getState(1: UserState user_state);
}