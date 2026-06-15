class GroupModel {
  final int id;
  String name;

  /// 小組頭貼遠端 URL（null = 未設定）
  String? avatarUrl;

  GroupModel({
    required this.id,
    this.name = '',
    this.avatarUrl,
  });
}
