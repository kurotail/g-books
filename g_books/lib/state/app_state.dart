import 'package:flutter/foundation.dart';
import '../data/models/group_model.dart';
import '../data/models/roster_student.dart';
import '../data/models/staff_account.dart';
import '../data/mock_data.dart';
import '../data/component_data.dart' show applyHeritageConfig;
import '../services/avatar_service.dart';
import '../services/api_client.dart';
import '../services/heritage_config_service.dart' show StudentConfigLoader;

/// 登入時自動綁定的古蹟（目前單一座；多古蹟時改由教師指派 / 學生選擇）。
const String _kDefaultHeritageId = 'beigang_chaotian_temple';

/// App 全域狀態（學生端 + 後台 session）。
///
/// 新模型「一組一帳號」：一個登入帳號 = 一個小組（[currentGroup]，name=username、
/// 頭像=帳號 pfp）；組員是後端 `students` 名冊（[groupMembers]，非帳號）。
class AppState extends ChangeNotifier {
  final AvatarService avatarService;

  /// 串接後端時用：登入 / 取資料走 [ApiClient]；mock 模式為 null。
  final ApiClient? _api;
  final bool _useBackend;

  /// 學生端執行設定載入器：登入後依 building_id 取後端設定並快取本機（離線回退）。
  final StudentConfigLoader? _configLoader;

  // ── 學生（小組）session ─────────────────────────────────────────────────────
  bool _loggedIn = false;
  GroupModel? _group; // 登入的小組（name=username、avatarUrl=帳號 pfp）
  List<RosterStudent> _members = const []; // 本組名冊成員
  bool _setupComplete = false;
  int _buildingId = 0;
  String? _assignedHeritageId;
  String? _password; // 改名（=改 username）後需以新名重登，故記住密碼

  // ── 後台（教師 / 管理者）session ───────────────────────────────────────────
  StaffAccount? _currentStaff;

  AppState({
    AvatarService? avatarService,
    ApiClient? apiClient,
    bool useBackend = false,
    StudentConfigLoader? configLoader,
  })  : avatarService = avatarService ?? MockAvatarService(),
        _api = apiClient,
        _useBackend = useBackend,
        _configLoader = configLoader;

  bool get isLoggedIn => _loggedIn;
  bool get isSetupComplete => _setupComplete;
  GroupModel? get currentGroup => _group;

  /// 目前小組的全部組員（後端名冊，依學號遞增）。供小組總攬列出卡片用。
  List<RosterStudent> get groupMembers => _members;

  /// 後端模式下、登入後依指派 building 解析出的古蹟 id（heritageId = building.name）。
  /// 目前畫面仍以 mock 的 assigned 古蹟為準，此值保留供日後多古蹟接線。
  String? get assignedHeritageId => _assignedHeritageId;

  StaffAccount? get currentStaff => _currentStaff;
  bool get isStaffLoggedIn => _currentStaff != null;
  StaffRole? get staffRole => _currentStaff?.role;

  /// 依學號取得本組某位組員（小組總攬點卡片改頭像時用）。
  RosterStudent? memberById(int id) {
    for (final m in _members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 把登入請求的例外轉成顯示用訊息：401 用 [on401]、其餘 [ApiException] 帶狀態碼、
  /// 連線失敗給通用訊息。
  static String _loginErrorMessage(Object e, {required String on401}) {
    if (e is ApiException) {
      return e.statusCode == 401 ? on401 : '登入失敗（${e.statusCode}）';
    }
    return '無法連線到伺服器，請確認網路與後端位址';
  }

  /// 以教師 / 管理者帳密登入。成功回 null、失敗回錯誤訊息。
  /// - 後端模式：打 `/api/login` 取 JWT，再 `GET /api/users` 找自己讀 role
  ///   （登入本身不回角色）：role=2→管理者（古蹟編輯器）、role=1→教師（控制台）、
  ///   role=0（小組）拒絕。
  /// - mock 模式：比對本機 [mockStaff]（admin / teacher 角色）。
  Future<String?> loginAsStaff(String username, String password) async {
    final u = username.trim();
    if (_useBackend && _api != null) {
      try {
        await _api.login(u, password);
      } catch (e) {
        return _loginErrorMessage(e, on401: '帳號或密碼錯誤');
      }
      // 讀自己的 role 決定後台。GET /api/users 任何登入者皆可呼叫。
      int role = 0;
      try {
        final me = await _fetchSelf(u);
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

  /// 學生（小組）登入：輸入組帳號 + 密碼。成功回 null、失敗回錯誤訊息。
  /// - 後端模式：`/api/login` 取 JWT → `GET /api/users` 找自己（取 building / 組徽 /
  ///   名冊）→ 自動綁定古蹟 → 取設定 → 取名冊成員。role≠0 視為非小組帳號而拒絕。
  /// - mock 模式：比對本機 [mockGroupAccounts] / [mockGroupPasswords]。
  Future<String?> login(String username, String password) async {
    final u = username.trim();
    final p = password;
    if (u.isEmpty || p.isEmpty) return '請輸入帳號與密碼';

    if (_useBackend && _api != null) {
      try {
        await _api.login(u, p);
      } catch (e) {
        return _loginErrorMessage(e, on401: '帳號或密碼錯誤');
      }
      Map<String, dynamic> me;
      try {
        me = await _fetchSelf(u);
      } catch (_) {
        _api.clearTokens();
        return '無法取得帳號資料，請稍後再試';
      }
      if (me.isEmpty) {
        _api.clearTokens();
        return '找不到此帳號資料';
      }
      if (((me['role'] as num?)?.toInt() ?? 0) != 0) {
        _api.clearTokens();
        return '此帳號非小組帳號，請改用教師 / 管理者登入';
      }

      _password = p;
      _buildingId = (me['building_id'] as num?)?.toInt() ?? 0;
      final pfp = (me['profile_pic_url'] as String?) ?? '';
      final studentIds = ((me['students'] as List?) ?? const [])
          .map((x) => (x as num).toInt())
          .toList();
      _group = GroupModel(id: 0, name: u, avatarUrl: pfp.isEmpty ? null : pfp);
      _setupComplete = pfp.isNotEmpty; // 已設組徽＝視為已完成首次設定
      _loggedIn = true;

      // 單一古蹟：登入時自動把本帳號綁到該 building（後端要求有 building 才能採集）。
      await _ensureBuildingBound();
      // 依 building_id 取後端古蹟設定並套用（失敗不擋登入）。
      await _loadAssignedConfig();
      // 取本組名冊成員（含頭像）。
      await _loadMembers(studentIds);
      notifyListeners();
      return null;
    }

    // mock：比對本機組帳號 + 密碼。
    final match = mockGroupAccounts.where((g) => g.username == u).toList();
    if (match.isEmpty || mockGroupPasswords[u] != p) {
      return '帳號或密碼錯誤';
    }
    final g = match.first;
    _group = GroupModel(id: 0, name: u, avatarUrl: g.avatarUrl);
    _members = [
      for (final id in g.studentIds) ?_rosterById(id),
    ]..sort((a, b) => a.id.compareTo(b.id));
    _setupComplete = g.avatarUrl != null;
    _loggedIn = true;
    notifyListeners();
    return null;
  }

  /// `GET /api/users` 取全部使用者，挑出 username == [u] 的那筆（找不到回空 map）。
  Future<Map<String, dynamic>> _fetchSelf(String u) async {
    final m = await _api!.getJson('/api/users') as Map<String, dynamic>;
    final users = (m['users'] as List?) ?? const [];
    return users.cast<Map<String, dynamic>>().firstWhere(
          (x) => (x['username'] as String?) == u,
          orElse: () => <String, dynamic>{},
        );
  }

  /// 確保本帳號已綁定到單一古蹟（[_kDefaultHeritageId]）。找出該 building 的 id，
  /// 若自己尚未綁或綁錯則 `POST /api/users/building`（設自己的）。失敗不擋登入。
  Future<void> _ensureBuildingBound() async {
    final api = _api;
    if (api == null) return;
    try {
      final list = await api.getJson('/api/building');
      if (list is! List) return;
      int targetId = 0;
      for (final b in list) {
        final m = (b as Map).cast<String, dynamic>();
        if ((m['name'] as String?) == _kDefaultHeritageId) {
          targetId = (m['building_id'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      if (targetId > 0 && targetId != _buildingId) {
        await api.sendJson('POST', '/api/users/building',
            body: {'building_id': targetId});
        _buildingId = targetId;
      }
    } catch (_) {
      // 綁定失敗不擋登入（採集時後端會再以 400 提示無 building）。
    }
  }

  /// 依 building_id 取後端古蹟設定並套用到執行中資料（[applyHeritageConfig]）。
  /// 線上成功會順手快取本機；離線回退讀快取。任何失敗都吞掉、不擋登入。
  Future<void> _loadAssignedConfig() async {
    final loader = _configLoader;
    if (loader == null) return;
    try {
      final r = await loader.load(_buildingId);
      if (r != null && r.heritageId.isNotEmpty) {
        _assignedHeritageId = r.heritageId;
        applyHeritageConfig(r.heritageId, r.config);
      }
    } catch (_) {
      // 設定載入失敗不擋登入。
    }
  }

  /// 取本組名冊成員：`GET /api/student` 拿全班名冊，依本組 [ids] 挑出並保留頭像。
  /// 失敗不擋登入（組員清單留空）。
  Future<void> _loadMembers(List<int> ids) async {
    final api = _api;
    if (api == null) {
      _members = const [];
      return;
    }
    try {
      final list = await api.getJson('/api/student');
      final all = <int, RosterStudent>{};
      if (list is List) {
        for (final s in list) {
          final m = (s as Map).cast<String, dynamic>();
          final id = (m['student_id'] as num?)?.toInt() ?? 0;
          final pic = (m['profile_pic_url'] as String?) ?? '';
          all[id] = RosterStudent(
            id: id,
            name: (m['name'] as String?) ?? '',
            avatarUrl: pic.isEmpty ? null : pic,
          );
        }
      }
      _members = [
        for (final id in ids) ?all[id],
      ]..sort((a, b) => a.id.compareTo(b.id));
    } catch (_) {
      _members = const [];
    }
  }

  RosterStudent? _rosterById(int id) {
    for (final s in mockRoster) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 設定某位組員的個人頭像（小組總攬編輯後呼叫）。後端模式同步 `PUT /api/student/{id}`
  /// （整筆覆蓋，需帶 name）。注意：後端目前僅教師 / 管理者可改名冊，學生組帳號會被擋
  /// （403）→ 僅本機預覽、不持久化（待後端放寬「同組可改組內頭像」）。
  void setMemberAvatarUrl(int studentId, String? url) {
    final i = _members.indexWhere((m) => m.id == studentId);
    if (i < 0) return;
    final old = _members[i];
    _members = List<RosterStudent>.from(_members)
      ..[i] = RosterStudent(id: old.id, name: old.name, avatarUrl: url);
    if (_useBackend && _api != null) {
      _api
          .sendJson('PUT', '/api/student/$studentId', body: {
            'name': old.name,
            'profile_pic_url': url ?? '', // 空字串＝清除
          })
          .catchError((_) => null); // 非教師遭 403 等失敗：保留本機預覽
    }
    notifyListeners();
  }

  /// 設定小組頭像（組徽）。後端模式同步 `POST /api/users/pfp`（設自己，省略 username）。
  void setGroupAvatarUrl(String? url) {
    _group?.avatarUrl = url;
    if (_useBackend && _api != null) {
      _api
          .sendJson('POST', '/api/users/pfp',
              body: {'profile_pic_url': url ?? ''})
          .catchError((_) => null);
    }
    notifyListeners();
  }

  /// 小組命名 = 改自己的登入帳號 username（`POST /api/users/username`）。成功回 null、
  /// 失敗回錯誤訊息。後端改名後舊 token 立即失效，故成功後以「新名 + 記住的密碼」透明
  /// 重新登入一次（使用者無感）。
  Future<String?> setGroupName(String name) async {
    final newName = name.trim();
    if (newName.isEmpty) return '請輸入小組名稱';
    if (newName == _group?.name) return null; // 沒變

    if (_useBackend && _api != null) {
      try {
        await _api.sendJson('POST', '/api/users/username',
            body: {'username': newName});
      } on ApiException catch (e) {
        return e.statusCode == 409 ? '此組名已被使用，請換一個' : '命名失敗（${e.statusCode}）';
      } catch (_) {
        return '命名失敗，請稍後再試';
      }
      // 改名後舊 token 失效 → 用新名 + 記住的密碼重登。
      final pw = _password;
      if (pw != null) {
        try {
          await _api.login(newName, pw);
        } catch (_) {
          return '已改名，請重新登入';
        }
      }
    }
    _group?.name = newName;
    notifyListeners();
    return null;
  }

  void completeSetup() {
    _setupComplete = true;
    notifyListeners();
  }

  void logout() {
    _loggedIn = false;
    _group = null;
    _members = const [];
    _setupComplete = false;
    _buildingId = 0;
    _assignedHeritageId = null;
    _password = null;
    _currentStaff = null;
    _api?.clearTokens();
    notifyListeners();
  }
}
