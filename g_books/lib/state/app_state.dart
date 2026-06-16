import 'package:flutter/foundation.dart';
import '../data/models/user_model.dart';
import '../data/models/group_model.dart';
import '../data/models/staff_account.dart';
import '../data/mock_data.dart';
import '../data/component_data.dart' show applyHeritageConfig;
import '../services/avatar_service.dart';
import '../services/api_client.dart';
import '../services/heritage_config_service.dart' show StudentConfigLoader;

class AppState extends ChangeNotifier {
  UserModel? _currentUser;
  StaffAccount? _currentStaff;
  final List<GroupModel> _groups = List.from(mockGroups);
  final AvatarService avatarService;

  /// 串接後端時用：登入 / 取小組走 [ApiClient]；mock 模式為 null。
  final ApiClient? _api;
  final bool _useBackend;

  /// 學生端執行設定載入器：登入後依 building_id 取後端設定並快取本機（離線回退）。
  final StudentConfigLoader? _configLoader;

  // 後端模式下登入後從 `GET /api/group` 取得的小組與成員（mock 模式不使用）。
  GroupModel? _backendGroup;
  List<UserModel> _backendMembers = const [];
  int _backendBuildingId = 0;
  String? _assignedHeritageId;

  AppState({
    AvatarService? avatarService,
    ApiClient? apiClient,
    bool useBackend = false,
    StudentConfigLoader? configLoader,
  })  : avatarService = avatarService ?? MockAvatarService(),
        _api = apiClient,
        _useBackend = useBackend,
        _configLoader = configLoader;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isSetupComplete => _currentUser?.hasCompletedSetup ?? false;

  /// 後端模式下、該組被指派的 building id（0 = 未指派）。對應古蹟由 building 解析。
  int get buildingId => _backendBuildingId;

  /// 後端模式下、登入後依指派 building 解析出的古蹟 id（heritageId = building.name）。
  String? get assignedHeritageId => _assignedHeritageId;

  // ── 後台（教師 / 管理者）session ───────────────────────────────────────────
  StaffAccount? get currentStaff => _currentStaff;
  bool get isStaffLoggedIn => _currentStaff != null;
  StaffRole? get staffRole => _currentStaff?.role;

  /// 以教師 / 管理者帳密登入。成功回 null、失敗回錯誤訊息。
  /// - 後端模式：打 `/api/login` 取 JWT，再 `GET /api/users` 找自己讀 role
  ///   （登入本身不回角色）：role=2→管理者（古蹟編輯器）、role=1→教師（控制台）、
  ///   role=0（學生）拒絕。
  /// - mock 模式：比對本機 [mockStaff]（admin / teacher 角色）。
  Future<String?> loginAsStaff(String username, String password) async {
    final u = username.trim();
    if (_useBackend && _api != null) {
      try {
        await _api.login(u, password);
      } on ApiException catch (e) {
        return e.statusCode == 401 ? '帳號或密碼錯誤' : '登入失敗（${e.statusCode}）';
      } catch (_) {
        return '無法連線到伺服器，請確認網路與後端位址';
      }
      // 讀自己的 role 決定後台。GET /api/users 任何登入者皆可呼叫。
      int role = 0;
      try {
        final m = await _api.getJson('/api/users') as Map<String, dynamic>;
        final users = (m['users'] as List?) ?? const [];
        final me = users.cast<Map<String, dynamic>>().firstWhere(
              (x) => (x['username'] as String?) == u,
              orElse: () => const {},
            );
        role = (me['role'] as num?)?.toInt() ?? 0;
      } catch (_) {
        _api.clearTokens();
        return '無法取得帳號權限，請稍後再試';
      }
      if (role < 1) {
        _api.clearTokens();
        return '此帳號非教師或管理者';
      }
      _currentStaff = StaffAccount(
        username: u,
        password: '',
        displayName: u,
        role: role >= 2 ? StaffRole.admin : StaffRole.teacher,
      );
      notifyListeners();
      return null;
    }
    try {
      _currentStaff = mockStaff.firstWhere(
        (a) => a.username == u && a.password == password,
      );
      notifyListeners();
      return null;
    } catch (_) {
      return '帳號或密碼錯誤';
    }
  }

  GroupModel? get currentGroup {
    if (_useBackend) return _backendGroup;
    if (_currentUser == null) return null;
    try {
      return _groups.firstWhere((g) => g.id == _currentUser!.groupId);
    } catch (_) {
      return null;
    }
  }

  /// 目前小組的全部組員，依座號遞增。供小組總攬列出卡片用。
  List<UserModel> get groupMembers {
    if (_useBackend) return _backendMembers;
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
    if (_useBackend) {
      try {
        return _backendMembers.firstWhere((u) => u.seatNumber == seatNumber);
      } catch (_) {
        return null;
      }
    }
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

  /// 學生登入：任一組員輸入姓名 + 座號即登入該組（不分組長）。
  /// - 後端模式：以 `username=姓名_座號`、`password=座號` 打 `/api/login`，成功後
  ///   `GET /api/group` 取小組與成員。
  /// - mock 模式：比對本機名冊。
  /// 成功回 null、失敗回錯誤訊息。
  Future<String?> login(String name, String seatNumber) async {
    final n = name.trim();
    final s = seatNumber.trim();
    if (n.isEmpty || s.isEmpty) return '請輸入姓名與座號';

    if (_useBackend && _api != null) {
      try {
        await _api.login('${n}_$s', s); // username=姓名_座號, password=座號
      } on ApiException catch (e) {
        return e.statusCode == 401 ? '姓名或座號錯誤' : '登入失敗（${e.statusCode}）';
      } catch (_) {
        return '無法連線到伺服器，請確認網路與後端位址';
      }
      try {
        final g = await _api.getJson('/api/group') as Map<String, dynamic>;
        _applyBackendGroup(g, selfName: n, selfSeat: s);
      } on ApiException catch (e) {
        return e.statusCode == 404 ? '此帳號尚未被分配到小組' : '取得小組資料失敗（${e.statusCode}）';
      } catch (_) {
        return '無法取得小組資料';
      }
      // 依該組 building_id 取後端古蹟設定（slot/原料名稱/等級/可放對應）並套用；
      // 失敗不擋登入（板面退回本機快取或現有資料）。
      await _loadAssignedConfig();
      notifyListeners();
      return null;
    }

    // mock：任一組員皆可登入（不再限組長）。
    try {
      final user = mockUsers.firstWhere(
        (u) => u.name == n && u.seatNumber == s,
      );
      _currentUser = user;
      notifyListeners();
      return null;
    } catch (_) {
      return '找不到此帳號，請確認姓名與座號';
    }
  }

  /// 套用後端 `GET /api/group` 回傳的小組：成員 username 為「姓名_座號」，解析回顯示用
  /// 的姓名 / 座號（後端尚未存姓名/頭像，故以 username 還原；頭像之後接端口）。
  void _applyBackendGroup(
    Map<String, dynamic> g, {
    required String selfName,
    required String selfSeat,
  }) {
    final gid = (g['group_id'] as num?)?.toInt() ?? 0;
    final rawName = (g['name'] as String?) ?? '';
    _backendBuildingId = (g['building_id'] as num?)?.toInt() ?? 0;
    // 後端未命名時預設 "Group <id>"，視為尚未命名 → 顯示空字串、走設定流程。
    final named = rawName.isNotEmpty && !RegExp(r'^Group \d+$').hasMatch(rawName);

    final members = <UserModel>[
      for (final u in ((g['members'] as List?) ?? const []).cast<String>())
        _userFromUsername(u, gid),
    ]..sort((a, b) => (int.tryParse(a.seatNumber) ?? 0)
        .compareTo(int.tryParse(b.seatNumber) ?? 0));

    _backendMembers = members;
    _backendGroup = GroupModel(id: gid, name: named ? rawName : '');
    _currentUser = UserModel(
      name: selfName,
      seatNumber: selfSeat,
      groupId: gid,
      isLeader: false,
      hasCompletedSetup: named,
    );
  }

  /// 依該組 building_id 取後端古蹟設定並套用到執行中資料（[applyHeritageConfig]）。
  /// 線上成功會順手快取本機；離線回退讀快取。取不到（未指派 building / 首次離線）時
  /// 不動現有資料。任何失敗都吞掉、不擋登入。
  Future<void> _loadAssignedConfig() async {
    final loader = _configLoader;
    if (loader == null) return;
    try {
      final r = await loader.load(_backendBuildingId);
      if (r != null && r.heritageId.isNotEmpty) {
        _assignedHeritageId = r.heritageId;
        applyHeritageConfig(r.heritageId, r.config);
      }
    } catch (_) {
      // 設定載入失敗不擋登入。
    }
  }

  UserModel _userFromUsername(String username, int gid) {
    final i = username.lastIndexOf('_');
    final name = i >= 0 ? username.substring(0, i) : username;
    final seat = i >= 0 ? username.substring(i + 1) : '';
    return UserModel(
      name: name,
      seatNumber: seat,
      groupId: gid,
      isLeader: false,
      hasCompletedSetup: true,
    );
  }

  /// 設定某位組員（含本人）的個人頭像，於小組總攬編輯後呼叫。
  /// （後端頭像端口尚未提供，目前僅本機；之後接上再同步。）
  void setMemberAvatarUrl(String seatNumber, String? url) {
    final member = memberBySeat(seatNumber);
    if (member == null) return;
    member.personalAvatarUrl = url;
    notifyListeners();
  }

  void setGroupAvatarUrl(String? url) {
    // 後端尚無小組頭像端口，先存本機。
    currentGroup?.avatarUrl = url;
    notifyListeners();
  }

  void setGroupName(String name) {
    currentGroup?.name = name;
    // 後端有 `POST /api/group/name`，順手同步（失敗不擋本機）。
    if (_useBackend && _api != null) {
      final gid = _backendGroup?.id;
      if (gid != null) {
        _api
            .sendJson('POST', '/api/group/name',
                body: {'group_id': gid, 'name': name})
            .catchError((_) => null);
      }
    }
    notifyListeners();
  }

  void completeSetup() {
    _currentUser?.hasCompletedSetup = true;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _currentStaff = null;
    _backendGroup = null;
    _backendMembers = const [];
    _backendBuildingId = 0;
    _assignedHeritageId = null;
    _api?.clearTokens();
    notifyListeners();
  }
}
