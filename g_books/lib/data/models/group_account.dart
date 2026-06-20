/// 一個小組的登入帳號（後端 `user`，role=0）。
///
/// 新模型「一組一帳號」：username 即組名（亦為登入帳號），帳號直接持有
/// 指派的古蹟（[buildingId]）、組徽（[avatarUrl]）與名冊成員（[studentIds]）。
class GroupAccount {
  final String username; // = 組名 / 登入帳號
  final int buildingId; // 指派的古蹟 building_id（0 = 未指派）
  final String? avatarUrl; // profile_pic_url（組徽；null / 空 = 無）
  final List<int> studentIds; // 指派到本組的名冊學生 id（遞增）

  const GroupAccount({
    required this.username,
    this.buildingId = 0,
    this.avatarUrl,
    this.studentIds = const [],
  });
}
