class GroupModel {
  final int id;
  String name;
  String? avatarPath;

  GroupModel({
    required this.id,
    this.name = '',
    this.avatarPath,
  });
}
