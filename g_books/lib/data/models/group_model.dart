class GroupModel {
  final int id;

  /// 顯示名稱 display_name（小組自取、可改）。
  String name;

  /// 登入帳號 username（老師建立帳號時設定，不可改）。
  final String username;

  /// 小組頭貼遠端 URL（null = 未設定）
  String? avatarUrl;

  GroupModel({
    required this.id,
    this.name = '',
    this.username = '',
    this.avatarUrl,
  });
}
