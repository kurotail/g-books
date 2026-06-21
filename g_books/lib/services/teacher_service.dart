import '../data/models/group_account.dart';
import '../data/models/roster_student.dart';
import '../data/mock_data.dart';
import 'api_client.dart';
import 'game_state_service.dart';
import 'heritage_config_service.dart' show buildingIdOf, buildingNameOf;

/// 教師控制台看到的一座古蹟 building（把「上課古蹟」對應到後端 building_id）。
class TeacherBuilding {
  final int id;
  final String name; // = heritageId
  const TeacherBuilding({required this.id, required this.name});
}

/// 教師控制台的後端操作抽象層。新模型「一組一帳號 + 班級名冊」：
///   - 班級名冊（students 表）：每筆 `{座號, 姓名, 頭像}`，非登入帳號。
///   - 小組帳號（user role=0）：username 即組名，持有指派的名冊成員與古蹟。
///
/// 對應 `gb_api` 端點：
///   - [setPhase]          ↔ `POST /api/state`
///   - [listRoster]        ↔ `GET /api/student`
///   - [createStudent]     ↔ `POST /api/student`
///   - [updateStudent]     ↔ `PUT /api/student/{id}`
///   - [deleteStudent]     ↔ `DELETE /api/student/{id}`
///   - [listGroups]        ↔ `GET /api/users`（取 role=0）
///   - [createGroup]       ↔ `POST /api/register`（role=0）
///   - [deleteGroup]       ↔ `DELETE /api/users/{username}`
///   - [setGroupStudents]  ↔ `POST /api/users/students`
///   - [setGroupAvatar]    ↔ `POST /api/users/pfp`
///   - [listBuildings]     ↔ `GET /api/building`
///
/// Mock 版操作本機資料（並透過 [MockGameStateService] 切換階段，方便單機 demo）；
/// 換真後端只要在 `main.dart` 改用 [ApiTeacherService]，UI 不需更動。
abstract class TeacherService {
  /// 切換遊戲階段。[duration] 為該階段時長（用於倒數 / 時間到自動結束）；mock 會帶給
  /// 共用的 GameStateService，後端則換算成 `/api/state` 的 end_time（到時自動回 NORMAL、
  /// 學生端以同一結束時間同步倒數）。
  Future<void> setPhase(GamePhase phase, {Duration? duration});

  // ── 班級名冊（students 表）─────────────────────────────────────────────────
  Future<List<RosterStudent>> listRoster();

  /// 新增名冊學生（座號為前端指定的主鍵）。座號已存在時拋例外。
  Future<void> createStudent({
    required int id,
    required String name,
    String? avatarUrl,
  });

  /// 覆寫名冊學生的姓名 / 頭像（座號不可改）。
  Future<void> updateStudent({
    required int id,
    required String name,
    String? avatarUrl,
  });

  /// 刪除名冊學生（後端會連動從各組 roster 移除）。
  Future<void> deleteStudent({required int id});

  // ── 小組帳號（user role=0）────────────────────────────────────────────────
  Future<List<GroupAccount>> listGroups();

  /// 建立小組登入帳號（username 即組名、role=0）。帳號已存在時拋例外。
  Future<void> createGroup({
    required String username,
    required String password,
  });

  /// 刪除一個小組帳號。
  Future<void> deleteGroup({required String username});

  /// 全量設定某組的名冊成員（整組覆蓋）。
  Future<void> setGroupStudents({
    required String username,
    required List<int> studentIds,
  });

  /// 設定某組的組徽（空字串＝清除）。
  Future<void> setGroupAvatar({required String username, String? avatarUrl});

  /// 列出後端所有古蹟 building，供「上課古蹟」把 heritageId 解析成 building_id。
  Future<List<TeacherBuilding>> listBuildings();

  // ── 題庫匯入（POST /api/question/upload）────────────────────────────────────
  /// 上傳題目音檔（敘述 / 選項 / 語音作答參考），回傳 `/audio/..` URL。
  Future<String> uploadQuestionAudio(List<int> bytes, String filename);

  /// 批次上傳題目（payload 形狀同後端 QuestionInput）。回傳逐題結果（與送出順序對應）。
  Future<List<QuestionUploadResult>> uploadQuestions(
    List<Map<String, dynamic>> questions,
  );
}

/// 單題上傳結果（對應後端 `POST /api/question/upload` 的 207 Multi-Status 每筆）。
class QuestionUploadResult {
  const QuestionUploadResult({
    required this.index,
    required this.status,
    this.id,
    this.error,
  });

  final int index;
  final int status; // 201=建立成功、400=該題不合法
  final int? id;
  final String? error;

  bool get created => status == 201;
}

/// 把 [GamePhase] 轉成後端的狀態字串。
String gamePhaseToState(GamePhase p) => switch (p) {
  GamePhase.quiz1 => 'QUIZ1',
  GamePhase.quiz2 => 'QUIZ2',
  GamePhase.normal => 'NORMAL',
};

/// 本機 mock：名冊 / 小組帳號由 [mockRoster] / [mockGroupAccounts] 種子化；切換階段
/// 直接推給共用的 [MockGameStateService]（單機時學生畫面會立即反映，方便 demo）。
class MockTeacherService implements TeacherService {
  MockTeacherService(this._gameState) {
    _roster.addAll(mockRoster);
    _groups.addAll(mockGroupAccounts);
  }

  final MockGameStateService _gameState;
  final List<RosterStudent> _roster = [];
  final List<GroupAccount> _groups = [];

  @override
  Future<void> setPhase(GamePhase phase, {Duration? duration}) async =>
      _gameState.pushPhase(phase, duration: duration);

  @override
  Future<List<RosterStudent>> listRoster() async {
    final list = List<RosterStudent>.from(_roster)
      ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  @override
  Future<void> createStudent({
    required int id,
    required String name,
    String? avatarUrl,
  }) async {
    if (_roster.any((s) => s.id == id)) {
      throw Exception('座號 $id 已存在');
    }
    _roster.add(RosterStudent(id: id, name: name, avatarUrl: avatarUrl));
  }

  @override
  Future<void> updateStudent({
    required int id,
    required String name,
    String? avatarUrl,
  }) async {
    final i = _roster.indexWhere((s) => s.id == id);
    if (i < 0) throw Exception('座號 $id 不存在');
    _roster[i] = RosterStudent(id: id, name: name, avatarUrl: avatarUrl);
  }

  @override
  Future<void> deleteStudent({required int id}) async {
    _roster.removeWhere((s) => s.id == id);
    // 連動：從各組 roster 移除。
    for (var i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (g.studentIds.contains(id)) {
        _groups[i] = GroupAccount(
          username: g.username,
          buildingId: g.buildingId,
          avatarUrl: g.avatarUrl,
          studentIds: g.studentIds.where((x) => x != id).toList(),
        );
      }
    }
  }

  @override
  Future<List<GroupAccount>> listGroups() async {
    final list = List<GroupAccount>.from(_groups)
      ..sort((a, b) => a.username.compareTo(b.username));
    return list;
  }

  @override
  Future<void> createGroup({
    required String username,
    required String password,
  }) async {
    if (_groups.any((g) => g.username == username)) {
      throw Exception('帳號 $username 已存在');
    }
    _groups.add(GroupAccount(username: username));
    mockGroupPasswords[username] = password;
  }

  @override
  Future<void> deleteGroup({required String username}) async {
    _groups.removeWhere((g) => g.username == username);
    mockGroupPasswords.remove(username);
  }

  @override
  Future<void> setGroupStudents({
    required String username,
    required List<int> studentIds,
  }) async {
    final i = _groups.indexWhere((g) => g.username == username);
    if (i < 0) return;
    final g = _groups[i];
    final valid =
        studentIds.where((id) => _roster.any((s) => s.id == id)).toList()
          ..sort();
    _groups[i] = GroupAccount(
      username: g.username,
      buildingId: g.buildingId,
      avatarUrl: g.avatarUrl,
      studentIds: valid,
    );
  }

  @override
  Future<void> setGroupAvatar({
    required String username,
    String? avatarUrl,
  }) async {
    final i = _groups.indexWhere((g) => g.username == username);
    if (i < 0) return;
    final g = _groups[i];
    _groups[i] = GroupAccount(
      username: g.username,
      buildingId: g.buildingId,
      avatarUrl: (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
      studentIds: g.studentIds,
    );
  }

  @override
  Future<List<TeacherBuilding>> listBuildings() async => const [
    TeacherBuilding(id: 1, name: 'beigang_chaotian_temple'),
  ];

  @override
  Future<String> uploadQuestionAudio(List<int> bytes, String filename) async =>
      '/audio/mock_$filename';

  @override
  Future<List<QuestionUploadResult>> uploadQuestions(
    List<Map<String, dynamic>> questions,
  ) async => [
    for (var i = 0; i < questions.length; i++)
      QuestionUploadResult(index: i, status: 201, id: i + 1),
  ];
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
      body['end_time'] = DateTime.now().toUtc().add(duration).toIso8601String();
    }
    await _client.sendJson('POST', '/api/state', body: body);
  }

  // ── 班級名冊 ─────────────────────────────────────────────────────────────
  @override
  Future<List<RosterStudent>> listRoster() async {
    final list = await _client.getJson('/api/student');
    if (list is! List) return const [];
    final out = [
      for (final s in list) _studentOf((s as Map).cast<String, dynamic>()),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  @override
  Future<void> createStudent({
    required int id,
    required String name,
    String? avatarUrl,
  }) async {
    await _client.sendJson(
      'POST',
      '/api/student',
      body: {
        'student_id': id,
        'name': name,
        'profile_pic_url': avatarUrl ?? '',
      },
    );
  }

  @override
  Future<void> updateStudent({
    required int id,
    required String name,
    String? avatarUrl,
  }) async {
    await _client.sendJson(
      'PUT',
      '/api/student/$id',
      body: {'name': name, 'profile_pic_url': avatarUrl ?? ''},
    );
  }

  @override
  Future<void> deleteStudent({required int id}) async {
    await _client.sendJson('DELETE', '/api/student/$id');
  }

  // ── 小組帳號 ─────────────────────────────────────────────────────────────
  @override
  Future<List<GroupAccount>> listGroups() async {
    final m = await _client.getJson('/api/users') as Map<String, dynamic>;
    final users = (m['users'] as List?) ?? const [];
    final out = <GroupAccount>[];
    for (final u in users) {
      final mm = (u as Map).cast<String, dynamic>();
      if (((mm['role'] as num?)?.toInt() ?? 0) != 0) continue; // 只取小組（學生角色）
      out.add(_groupOf(mm));
    }
    out.sort((a, b) => a.username.compareTo(b.username));
    return out;
  }

  @override
  Future<void> createGroup({
    required String username,
    required String password,
  }) async {
    await _client.sendJson(
      'POST',
      '/api/register',
      body: {'username': username, 'password': password, 'role': 0},
    );
  }

  @override
  Future<void> deleteGroup({required String username}) async {
    // RESTful：DELETE /api/users/{username}（帳號走路徑、無 body）。username 可能含
    // 中文，需 URL-encode 後放進路徑。
    await _client.sendJson(
      'DELETE',
      '/api/users/${Uri.encodeComponent(username)}',
    );
  }

  @override
  Future<void> setGroupStudents({
    required String username,
    required List<int> studentIds,
  }) async {
    await _client.sendJson(
      'POST',
      '/api/users/students',
      body: {'username': username, 'student_ids': studentIds},
    );
  }

  @override
  Future<void> setGroupAvatar({
    required String username,
    String? avatarUrl,
  }) async {
    await _client.sendJson(
      'POST',
      '/api/users/pfp',
      body: {
        'username': username,
        'profile_pic_url': avatarUrl ?? '', // 空字串＝清除
      },
    );
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
  Future<String> uploadQuestionAudio(List<int> bytes, String filename) =>
      _client.uploadAudio(bytes, filename);

  @override
  Future<List<QuestionUploadResult>> uploadQuestions(
    List<Map<String, dynamic>> questions,
  ) async {
    final res = await _client.sendJson(
      'POST',
      '/api/question/upload',
      body: {'questions': questions},
    );
    final results = (res is Map ? res['results'] as List? : null) ?? const [];
    return [
      for (final r in results)
        QuestionUploadResult(
          index: ((r as Map)['index'] as num?)?.toInt() ?? 0,
          status: (r['status'] as num?)?.toInt() ?? 0,
          id: (r['id'] as num?)?.toInt(),
          error: r['error'] as String?,
        ),
    ];
  }

  RosterStudent _studentOf(Map<String, dynamic> m) {
    final pic = (m['profile_pic_url'] as String?) ?? '';
    return RosterStudent(
      id: (m['student_id'] as num?)?.toInt() ?? 0,
      name: (m['name'] as String?) ?? '',
      avatarUrl: pic.isEmpty ? null : pic,
    );
  }

  GroupAccount _groupOf(Map<String, dynamic> m) {
    final pic = (m['profile_pic_url'] as String?) ?? '';
    final ids =
        ((m['students'] as List?) ?? const [])
            .map((x) => (x as num).toInt())
            .toList()
          ..sort();
    return GroupAccount(
      username: (m['username'] as String?) ?? '',
      buildingId: (m['building_id'] as num?)?.toInt() ?? 0,
      avatarUrl: pic.isEmpty ? null : pic,
      studentIds: ids,
    );
  }
}
