import '../core/account_id.dart';
import '../data/mock_data.dart';
import 'api_client.dart';
import 'game_state_service.dart';
import 'heritage_config_service.dart' show buildingIdOf, buildingNameOf;

/// 教師控制台看到的一位學生（帳號 = 姓名_座號）。
class TeacherStudent {
  final String username; // 姓名_座號
  final String name;
  final String seat;
  final int groupId; // 0 = 未分組
  final String? avatarUrl; // 頭像（後端尚無端口；mock 取本機名冊、API 暫為 null）

  const TeacherStudent({
    required this.username,
    required this.name,
    required this.seat,
    required this.groupId,
    this.avatarUrl,
  });

  TeacherStudent copyWith({int? groupId}) => TeacherStudent(
        username: username,
        name: name,
        seat: seat,
        groupId: groupId ?? this.groupId,
        avatarUrl: avatarUrl,
      );
}

/// 教師控制台看到的一座古蹟 building（用於把「上課古蹟」對應到後端 building_id）。
class TeacherBuilding {
  final int id;
  final String name; // = heritageId
  const TeacherBuilding({required this.id, required this.name});
}

/// 教師控制台的後端操作抽象層。對應 `gb_api` 的教師端點：
///   - [setPhase]          ↔ `POST /api/state`
///   - [listStudents]      ↔ `GET /api/users`（取 role=student）
///   - [registerStudent]   ↔ `POST /api/register`（username=姓名_座號、password=座號）
///   - [assignGroup]       ↔ `POST /api/group/set`
///   - [renameGroup]       ↔ `POST /api/group/name`
///   - [listBuildings]     ↔ `GET /api/building`
///   - [setGroupBuilding]  ↔ `POST /api/group/building`
///
/// Mock 版操作本機資料（並透過 [MockGameStateService] 切換階段，方便單機 demo）；
/// 換真後端只要在 `main.dart` 改用 [ApiTeacherService]，UI 不需更動。
abstract class TeacherService {
  /// 切換遊戲階段。[duration] 為該階段時長（用於倒數 / 時間到自動結束）；mock 會帶給
  /// 共用的 GameStateService，後端則換算成 `/api/state` 的 end_time（到時自動回 NORMAL、
  /// 學生端以同一結束時間同步倒數）。
  Future<void> setPhase(GamePhase phase, {Duration? duration});
  Future<List<TeacherStudent>> listStudents();

  /// 建立學生帳號（username=姓名_座號、password=座號）。帳號已存在時拋例外。
  Future<void> registerStudent({
    required String name,
    required String seat,
    int groupId = 0,
  });

  /// 刪除一個學生帳號。重置進度＝對全部學生逐一呼叫此方法（前端 loop，後端不另設端點）。
  Future<void> deleteStudent({required String username});

  Future<void> assignGroup({required String username, required int groupId});
  Future<void> renameGroup({required int groupId, required String name});

  /// 列出後端所有古蹟 building，供「上課古蹟」把 heritageId 解析成 building_id。
  Future<List<TeacherBuilding>> listBuildings();

  /// 指派某組的上課古蹟（building）。
  Future<void> setGroupBuilding({required int groupId, required int buildingId});
}

/// 把 [GamePhase] 轉成後端的狀態字串。
String gamePhaseToState(GamePhase p) => switch (p) {
      GamePhase.quiz1 => 'QUIZ1',
      GamePhase.quiz2 => 'QUIZ2',
      GamePhase.normal => 'NORMAL',
    };

/// 本機 mock：學生名單由 [mockUsers] 種子化；切換階段直接推給共用的
/// [MockGameStateService]（單機時學生畫面會立即反映，方便 demo）。
class MockTeacherService implements TeacherService {
  MockTeacherService(this._gameState) {
    for (final u in mockUsers) {
      _students.add(TeacherStudent(
        username: usernameOf(u.name, u.seatNumber),
        name: u.name,
        seat: u.seatNumber,
        groupId: u.groupId,
        avatarUrl: u.personalAvatarUrl,
      ));
    }
  }

  final MockGameStateService _gameState;
  final List<TeacherStudent> _students = [];

  @override
  Future<void> setPhase(GamePhase phase, {Duration? duration}) async =>
      _gameState.pushPhase(phase, duration: duration);

  @override
  Future<List<TeacherStudent>> listStudents() async {
    final list = List<TeacherStudent>.from(_students);
    list.sort((a, b) {
      if (a.groupId != b.groupId) return a.groupId.compareTo(b.groupId);
      return (int.tryParse(a.seat) ?? 0).compareTo(int.tryParse(b.seat) ?? 0);
    });
    return list;
  }

  @override
  Future<void> registerStudent({
    required String name,
    required String seat,
    int groupId = 0,
  }) async {
    final username = usernameOf(name, seat);
    if (_students.any((s) => s.username == username)) {
      throw Exception('帳號 $username 已存在');
    }
    _students.add(TeacherStudent(
      username: username,
      name: name,
      seat: seat,
      groupId: groupId,
    ));
  }

  @override
  Future<void> deleteStudent({required String username}) async {
    _students.removeWhere((s) => s.username == username);
  }

  @override
  Future<void> assignGroup({
    required String username,
    required int groupId,
  }) async {
    final i = _students.indexWhere((s) => s.username == username);
    if (i >= 0) _students[i] = _students[i].copyWith(groupId: groupId);
  }

  @override
  Future<void> renameGroup({required int groupId, required String name}) async {
    // mock 無小組名稱儲存需求（學生端組名走另一路），此處僅為介面一致；no-op。
  }

  @override
  Future<List<TeacherBuilding>> listBuildings() async =>
      const [TeacherBuilding(id: 1, name: 'beigang_chaotian_temple')];

  @override
  Future<void> setGroupBuilding({
    required int groupId,
    required int buildingId,
  }) async {
    // mock 無 building 指派；no-op。
  }
}

/// 後端實作：教師端點皆需教師 JWT（由教師於 staff 登入時取得，存於共用 [ApiClient]）。
class ApiTeacherService implements TeacherService {
  ApiTeacherService(this._client);

  final ApiClient _client;

  @override
  Future<void> setPhase(GamePhase phase, {Duration? duration}) async {
    // 後端 `/api/state` 的 end_time：排程到時自動回 NORMAL，並讓學生端倒數以同一個
    // 結束時間同步（跨裝置一致）。NORMAL 不排程；無時長時不帶（後端視為不自動回復）。
    final body = <String, dynamic>{'state': gamePhaseToState(phase)};
    if (phase != GamePhase.normal &&
        duration != null &&
        duration > Duration.zero) {
      body['end_time'] =
          DateTime.now().toUtc().add(duration).toIso8601String();
    }
    await _client.sendJson('POST', '/api/state', body: body);
  }

  @override
  Future<List<TeacherStudent>> listStudents() async {
    final m = await _client.getJson('/api/users') as Map<String, dynamic>;
    final users = (m['users'] as List?) ?? const [];
    final out = <TeacherStudent>[];
    for (final u in users) {
      final mm = u as Map<String, dynamic>;
      if (((mm['role'] as num?)?.toInt() ?? 0) != 0) continue; // 只取學生
      final username = mm['username'] as String? ?? '';
      final (:name, :seat) = splitUsername(username);
      final pic = (mm['profile_pic_url'] as String?) ?? '';
      out.add(TeacherStudent(
        username: username,
        name: name,
        seat: seat,
        groupId: (mm['group_id'] as num?)?.toInt() ?? 0,
        avatarUrl: pic.isEmpty ? null : pic,
      ));
    }
    out.sort((a, b) {
      if (a.groupId != b.groupId) return a.groupId.compareTo(b.groupId);
      return (int.tryParse(a.seat) ?? 0).compareTo(int.tryParse(b.seat) ?? 0);
    });
    return out;
  }

  @override
  Future<void> registerStudent({
    required String name,
    required String seat,
    int groupId = 0,
  }) async {
    await _client.sendJson('POST', '/api/register', body: {
      'username': usernameOf(name, seat),
      'password': seat,
      'role': 0,
      if (groupId > 0) 'group_id': groupId,
    });
  }

  @override
  Future<void> deleteStudent({required String username}) async {
    // 後端改為 RESTful：DELETE /api/users/{username}（帳號走路徑、無 body）。
    // username 為「姓名_座號」含中文與底線，需 URL-encode 後放進路徑。
    await _client.sendJson(
        'DELETE', '/api/users/${Uri.encodeComponent(username)}');
  }

  @override
  Future<void> assignGroup({
    required String username,
    required int groupId,
  }) async {
    await _client.sendJson('POST', '/api/group/set',
        body: {'username': username, 'group_id': groupId});
  }

  @override
  Future<void> renameGroup({required int groupId, required String name}) async {
    await _client.sendJson('POST', '/api/group/name',
        body: {'group_id': groupId, 'name': name});
  }

  @override
  Future<List<TeacherBuilding>> listBuildings() async {
    final list = await _client.getJson('/api/building');
    if (list is! List) return const [];
    return [
      for (final b in list)
        TeacherBuilding(
          id: buildingIdOf((b as Map).cast<String, dynamic>()),
          name: buildingNameOf(b.cast<String, dynamic>()),
        ),
    ];
  }

  @override
  Future<void> setGroupBuilding({
    required int groupId,
    required int buildingId,
  }) async {
    await _client.sendJson('POST', '/api/group/building',
        body: {'group_id': groupId, 'building_id': buildingId});
  }
}
