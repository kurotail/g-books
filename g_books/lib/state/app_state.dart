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

  String? loginWithMock(String name, String seatNumber) {
    try {
      final user = mockUsers.firstWhere(
        (u) => u.name == name && u.seatNumber == seatNumber,
      );
      _currentUser = user;
      notifyListeners();
      return null;
    } catch (_) {
      return '找不到此帳號，請確認姓名與座號';
    }
  }

  // TODO(backend): 以真實登入 API 取代 loginWithMock。
  // 後端回傳應包含使用者基本資料與 isLeader / hasCompletedSetup（或等價的
  // 初次登入旗標），建立 UserModel 後 set _currentUser 即可，導向流程不變：
  //   非初次登入            → /heritage-selection
  //   初次登入 + 組長        → 個人頭貼 → 小組頭貼 → 小組命名 → 完成
  //   初次登入 + 組員        → 個人頭貼 → 完成

  void setPersonalAvatarUrl(String? url) {
    _currentUser?.personalAvatarUrl = url;
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
