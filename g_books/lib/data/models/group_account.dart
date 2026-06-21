/// 一個小組的登入帳號（後端 `user`，role=0）。
///
/// 新模型「一組一帳號」：username 即組名（亦為登入帳號），帳號直接持有
/// 指派的古蹟（[buildingId]）、組徽（[avatarUrl]）與名冊成員（[studentIds]）。
///
/// [id] 是後端使用者數字主鍵（`users.id`）。後端已把所有「指涉某使用者」的端點改用
/// `user_id`（設名冊 / 組徽、刪帳號皆然），故管理小組時要帶這個 id 而非 username。
class GroupAccount {
  final int id; // 後端 user_id（數字主鍵；mock 以遞增序號代替，0 = 未知）
  final String username; // = 組名 / 登入帳號
  final int buildingId; // 指派的古蹟 building_id（0 = 未指派）
  final String? avatarUrl; // profile_pic_url（組徽；null / 空 = 無）
  final List<int> studentIds; // 指派到本組的名冊學生 id（遞增）

  const GroupAccount({
    this.id = 0,
    required this.username,
    this.buildingId = 0,
    this.avatarUrl,
    this.studentIds = const [],
  });
}
