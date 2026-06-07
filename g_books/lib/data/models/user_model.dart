class UserModel {
  final String name;
  final String seatNumber;
  final int groupId;

  /// 是否為組長。預計由後端登入回傳決定（組長才需走小組頭貼／命名步驟）。
  final bool isLeader;

  /// 是否已完成初始設定。預計由後端登入回傳決定：
  /// false = 初次登入，需依 [isLeader] 顯示後續設定步驟；
  /// true  = 非初次登入，登入後直接進入選古蹟頁。
  bool hasCompletedSetup;

  /// 個人頭貼遠端 URL（null = 未設定）
  String? personalAvatarUrl;

  UserModel({
    required this.name,
    required this.seatNumber,
    required this.groupId,
    required this.isLeader,
    this.hasCompletedSetup = false,
    this.personalAvatarUrl,
  });

  /// 初次登入（尚未完成設定）。後端回傳 [hasCompletedSetup] 後即可判斷。
  bool get isFirstLogin => !hasCompletedSetup;
}
