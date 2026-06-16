// 學生後端帳號的識別字串：username = 姓名_座號、password = 座號。
// 此處集中組裝 / 解析，避免各處重複 '${name}_$seat' 與 lastIndexOf('_')。

/// 組出後端帳號 username（姓名_座號）。
String usernameOf(String name, String seat) => '${name}_$seat';

/// 拆解 username（姓名_座號）回姓名 / 座號。以最後一個底線切分（姓名本身可含底線）；
/// 無底線時整串視為姓名、座號為空。
({String name, String seat}) splitUsername(String username) {
  final i = username.lastIndexOf('_');
  if (i < 0) return (name: username, seat: '');
  return (name: username.substring(0, i), seat: username.substring(i + 1));
}
