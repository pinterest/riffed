include "account.thrift"

service SharedService {
  account.Account getAccount(1: i64 userId);
  account.Preferences getPreferences(1: i64 userId);
}