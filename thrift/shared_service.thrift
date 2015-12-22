include "status.thrift"
include "account.thrift"

struct AccountList {
  1: list<account.Account> accounts,
  2: status.Status status;
}

service SharedService {
  account.Account getAccount(1: i64 userId);
  account.Preferences getPreferences(1: i64 userId);
}
