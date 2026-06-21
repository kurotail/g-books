/// 班級名冊的一筆學生（後端 `students` 表）。
///
/// 注意：名冊學生**不是登入帳號**——登入帳號是「小組」（[GroupAccount]）。學生只是
/// 一筆 `{座號, 姓名, 頭像}` 資料，透過各組的 roster 指派到小組。
///
/// 唯一鍵是後端配發的 [id]（`student_id`，伺服器自動配發、唯讀）。座號（[seatNo]）只是
/// 顯示用、教師可指定的編號；後端 students 表沒有座號欄，故座號折進 `name` 以
/// `"座號_姓名"` 格式儲存（見 [encodeRosterName] / [decodeRosterName]），讀回時再拆開。
class RosterStudent {
  final int id; // student_id（後端配發、唯一鍵；mock 也以此為鍵）
  final int seatNo; // 座號（顯示用；折進後端 name 儲存，非唯一鍵）
  final String name; // 姓名（已從 "座號_姓名" 拆出的純姓名）
  final String? avatarUrl; // profile_pic_url（null / 空 = 無頭像）

  const RosterStudent({
    required this.id,
    required this.seatNo,
    required this.name,
    this.avatarUrl,
  });
}

/// 把座號 + 姓名折成後端 `name` 欄要存的字串：`"座號_姓名"`。
/// 後端 students 表沒有座號欄，故以此折疊保存教師指定的座號。
String encodeRosterName(int seatNo, String name) => '${seatNo}_$name';

/// 解析後端 `name`（`"座號_姓名"`）：以**第一個**底線分隔，前段為座號、後段為姓名。
/// 無底線、或底線前非數字（舊資料 / 外部建立）→ 座號回 0、整串視為姓名。
(int seatNo, String name) decodeRosterName(String stored) {
  final i = stored.indexOf('_');
  if (i < 0) return (0, stored);
  final seat = int.tryParse(stored.substring(0, i));
  if (seat == null) return (0, stored);
  return (seat, stored.substring(i + 1));
}
