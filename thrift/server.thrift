include "structures.thrift"

enum ActivityState {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: string firstName,
  2: string lastName,
  3: ActivityState state;
}

struct LoudUser {
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

struct ResponseWithMap {
  1: map<i64, User> users;
}

struct UserBoardResponse {
  1: User user,
  2: structures.Board board;
}

service Server {
  ConfigResponse config(1: ConfigRequest request, 2: i32 timestamp);
  ActivityState setUserState(1: User user, 2: ActivityState status);
  map<string, i32> dictFun(1: map<string, i32> dict);
  map<string, User> dictUserFun(1: map<string, User> dict);
  set<string> setFun(1: set<string> mySet);
  set<User> setUserFun(1: set<User> mySet);
  list<i32> listFun(1: list<i32> numbers);
  list<User> listUserFun(1: list<User> users);
  ActivityState getState(1: ActivityState user_state);
  ActivityState echoState(1: ActivityState state_to_echo);
  list<ActivityState> echoActivityStateList(1: list<ActivityState> states);
  ActivityState getTranslatedState(1: i32 stateAsInt);
  LoudUser getLoudUser();
  void setLoudUser(1: LoudUser user);
  map<string, ActivityState> getUserStates(1: list<string> usernames);
  string echoString(1: string input);
  set<ActivityState> getAllStates();
  ResponseWithMap getUsers(1: list<i64> userIds);
  void functionWithoutNumberedArgs(User user, i64 likeCount);
  map<i64, structures.MapResponse> getMapResponse();
  list<structures.ListResponse> getListResponse();
  set<structures.SetResponse> getSetResponse();
  map<i64, UserBoardResponse> getUserBoardResponse();
}
