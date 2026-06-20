/// 班級名冊的一筆學生（後端 `students` 表）。
///
/// 注意：名冊學生**不是登入帳號**——登入帳號是「小組」（[GroupAccount]）。學生只是
/// 一筆 `{學號, 姓名, 頭像}` 資料，透過各組的 roster 指派到小組。
class RosterStudent {
  final int id; // student_id（學號，由前端指定、為主鍵）
  final String name;
  final String? avatarUrl; // profile_pic_url（null / 空 = 無頭像）

  const RosterStudent({required this.id, required this.name, this.avatarUrl});
}
