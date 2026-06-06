import 'package:flutter/foundation.dart';
import '../data/models/user_model.dart';
import '../data/models/group_model.dart';
import '../data/mock_data.dart';

class AppState extends ChangeNotifier {
  UserModel? _currentUser;
  final List<GroupModel> _groups = List.from(mockGroups);

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isSetupComplete => _currentUser?.hasCompletedSetup ?? false;

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

  void setPersonalAvatar(String? path) {
    _currentUser?.personalAvatarPath = path;
    notifyListeners();
  }

  void setGroupAvatar(String? path) {
    currentGroup?.avatarPath = path;
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
