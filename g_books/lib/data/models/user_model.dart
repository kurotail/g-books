class UserModel {
  final String name;
  final String seatNumber;
  final int groupId;
  final bool isLeader;
  bool hasCompletedSetup;
  String? personalAvatarPath;

  UserModel({
    required this.name,
    required this.seatNumber,
    required this.groupId,
    required this.isLeader,
    this.hasCompletedSetup = false,
    this.personalAvatarPath,
  });
}
