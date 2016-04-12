struct Board {
  1: i64 id,
  2: i64 userId,
  3: string title,
  4: list<i64> pinIds
}

struct SetResponse {
  1: i64 setId;
}

struct MapResponse {
  1: i64 mapId;
}

struct ListResponse {
  1: i64 listId;
}

exception ServerException {
  1: string message,
  2: i32 code
}
