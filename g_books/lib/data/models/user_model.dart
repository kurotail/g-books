class UserModel {
  final String name;
  final String seatNumber;
  final int groupId;

  /// 是否為組長（組長才需走小組頭貼／命名步驟）。由後端登入回傳決定。
  final bool isLeader;

  /// 是否已完成初始設定：false = 初次登入需走後續設定步驟、true = 直接進選古蹟頁。
  bool hasCompletedSetup;

  /// 個人頭貼遠端 URL（null = 未設定）。
  String? personalAvatarUrl;

  UserModel({
    required this.name,
    required this.seatNumber,
    required this.groupId,
    required this.isLeader,
    this.hasCompletedSetup = false,
    this.personalAvatarUrl,
  });
}
