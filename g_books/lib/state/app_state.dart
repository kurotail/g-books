import 'package:flutter/foundation.dart';
import '../data/models/user_model.dart';
import '../data/models/group_model.dart';
import '../data/mock_data.dart';
import '../services/avatar_service.dart';

class AppState extends ChangeNotifier {
  UserModel? _currentUser;
  final List<GroupModel> _groups = List.from(mockGroups);
  final AvatarService avatarService;

  AppState({AvatarService? avatarService})
      : avatarService = avatarService ?? MockAvatarService();

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isSetupComplete => _currentUser?.hasCompletedSetup ?? false;

  /// 初次登入旗標。目前由 [UserModel.hasCompletedSetup]（mock）推導，
  /// 未來改為後端登入回傳值即可，無需更動導向邏輯。
  bool get isFirstLogin => _currentUser?.isFirstLogin ?? false;

  GroupModel? get currentGroup {
    if (_currentUser == null) return null;
    try {
      return _groups.firstWhere((g) => g.id == _currentUser!.groupId);
    } catch (_) {
      return null;
    }
  }

  /// 目前小組的全部組員，組長排第一、其餘依座號遞增。供小組總攬列出卡片用。
  List<UserModel> get groupMembers {
    final gid = _currentUser?.groupId;
    if (gid == null) return const [];
    final list = mockUsers.where((u) => u.groupId == gid).toList();
    list.sort((a, b) {
      if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
      return (int.tryParse(a.seatNumber) ?? 0)
          .compareTo(int.tryParse(b.seatNumber) ?? 0);
    });
    return list;
  }

  /// 依座號取得目前小組的某位組員（小組總攬點卡片改頭像時用）。
  UserModel? memberBySeat(String seatNumber) {
    final gid = _currentUser?.groupId;
    if (gid == null) return null;
    try {
      return mockUsers.firstWhere(
        (u) => u.groupId == gid && u.seatNumber == seatNumber,
      );
    } catch (_) {
      return null;
    }
  }

  /// 以組長帳號登入整組。非組長帳號會被擋下。
  String? loginWithMock(String name, String seatNumber) {
    try {
      final user = mockUsers.firstWhere(
        (u) => u.name == name && u.seatNumber == seatNumber,
      );
      if (!user.isLeader) return '請使用組長帳號登入';
      _currentUser = user;
      notifyListeners();
      return null;
    } catch (_) {
      return '找不到此帳號，請確認姓名與座號';
    }
  }

  // TODO(backend): 以真實登入 API 取代 loginWithMock。
  // 後端回傳應包含組長基本資料、小組成員清單與 hasCompletedSetup（或等價的
  // 初次登入旗標），建立 UserModel 後 set _currentUser 即可，導向流程不變：
  //   非初次登入   → /heritage-selection
  //   初次登入     → 小組頭像 → 小組命名 → 小組總攬（各組員設頭像）→ 進入遊戲

  /// 設定某位組員（含組長本人）的個人頭像，於小組總攬編輯後呼叫。
  void setMemberAvatarUrl(String seatNumber, String? url) {
    final member = memberBySeat(seatNumber);
    if (member == null) return;
    member.personalAvatarUrl = url;
    notifyListeners();
  }

  void setGroupAvatarUrl(String? url) {
    currentGroup?.avatarUrl = url;
    notifyListeners();
  }

  void setGroupName(String name) {
    currentGroup?.name = name;
    notifyListeners();
  }

  void completeSetup() {
    _currentUser?.hasCompletedSetup = true;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
