import '../data/mock_data.dart';
import '../data/models/staff_account.dart';
import 'api_client.dart';

/// 管理者後台「教師帳號管理」看到的一筆老師帳號（user role=1）。
/// 小組帳號（role=0）由教師控制台管理、管理者（role=2）不出現在此清單。
/// [id] 為後端使用者數字主鍵（`users.id`），刪除 / 改密皆以此指涉。
class TeacherAccount {
  final int id;
  final String username;
  final String? avatarUrl;
  const TeacherAccount({required this.id, required this.username, this.avatarUrl});
}

/// 管理者對「教師帳號」的後端操作抽象層。只管 role=1（老師）；不碰小組帳號。
/// 後端已把指涉使用者的端點改用數字 `user_id`。
///
/// 對應 `gb_api` 端點：
///   - [listTeachers]         ↔ `GET /api/users`（取 role=1）
///   - [createTeacher]        ↔ `POST /api/register`（role=1）
///   - [deleteTeacher]        ↔ `DELETE /api/users/{user_id}`
///   - [resetTeacherPassword] ↔ `POST /api/users/password`（**待後端開放**：
///       目前該端點只能改「自己」且要驗舊密碼；需比照 `SetProfilePic` 改成可帶
///       目標 `user_id`、且 teacher/admin 改他人時略過舊密碼驗證。後端補上前會回錯誤。)
///
/// Mock 版操作本機資料；換真後端只要在 `main.dart` 改用 [ApiAccountService]，UI 不變。
abstract class AccountService {
  Future<List<TeacherAccount>> listTeachers();

  /// 建立老師帳號（role=1）。帳號已存在時拋例外（後端回 409）。
  Future<void> createTeacher(
      {required String username, required String password});

  /// 刪除一個老師帳號（[userId] = 後端 user_id）。
  Future<void> deleteTeacher({required int userId});

  /// 重設某老師的密碼（管理者免舊密碼）。**需後端開放**，未開放前會拋例外。
  Future<void> resetTeacherPassword(
      {required int userId, required String newPassword});
}

/// 本機 mock：教師帳號從 [mockStaff] 的 teacher 角色種子化，密碼存在本機可變 map。
class MockAccountService implements AccountService {
  MockAccountService() {
    for (final s in mockStaff) {
      if (s.role == StaffRole.teacher) {
        final id = _nextId++;
        _teachers.add(TeacherAccount(id: id, username: s.username));
        _passwords[id] = s.password;
      }
    }
  }

  final List<TeacherAccount> _teachers = [];
  final Map<int, String> _passwords = {};
  int _nextId = 1;

  @override
  Future<List<TeacherAccount>> listTeachers() async {
    return List<TeacherAccount>.from(_teachers)
      ..sort((a, b) => a.username.compareTo(b.username));
  }

  @override
  Future<void> createTeacher(
      {required String username, required String password}) async {
    if (_teachers.any((t) => t.username == username)) {
      throw Exception('帳號 $username 已存在');
    }
    final id = _nextId++;
    _teachers.add(TeacherAccount(id: id, username: username));
    _passwords[id] = password;
  }

  @override
  Future<void> deleteTeacher({required int userId}) async {
    _teachers.removeWhere((t) => t.id == userId);
    _passwords.remove(userId);
  }

  @override
  Future<void> resetTeacherPassword(
      {required int userId, required String newPassword}) async {
    if (!_teachers.any((t) => t.id == userId)) throw Exception('帳號不存在');
    _passwords[userId] = newPassword;
  }
}

/// 後端實作：皆需管理者 JWT（管理者於 staff 登入時取得，存於共用 [ApiClient]）。
class ApiAccountService implements AccountService {
  ApiAccountService(this._client);

  final ApiClient _client;

  @override
  Future<List<TeacherAccount>> listTeachers() async {
    final m = await _client.getJson('/api/users') as Map<String, dynamic>;
    final users = (m['users'] as List?) ?? const [];
    final out = <TeacherAccount>[];
    for (final u in users) {
      final mm = (u as Map).cast<String, dynamic>();
      if (((mm['role'] as num?)?.toInt() ?? 0) != 1) continue; // 只取老師
      final pic = (mm['profile_pic_url'] as String?) ?? '';
      out.add(TeacherAccount(
        id: (mm['id'] as num?)?.toInt() ?? 0,
        username: (mm['username'] as String?) ?? '',
        avatarUrl: pic.isEmpty ? null : pic,
      ));
    }
    out.sort((a, b) => a.username.compareTo(b.username));
    return out;
  }

  @override
  Future<void> createTeacher(
      {required String username, required String password}) async {
    await _client.sendJson('POST', '/api/register', body: {
      'username': username,
      'password': password,
      'role': 1, // 老師
    });
  }

  @override
  Future<void> deleteTeacher({required int userId}) async {
    await _client.sendJson('DELETE', '/api/users/$userId');
  }

  @override
  Future<void> resetTeacherPassword(
      {required int userId, required String newPassword}) async {
    // 帶目標 user_id + 新密碼（不帶舊密碼）。後端比照 SetProfilePic 開放
    // 「teacher/admin 改他人」後即生效；未開放前後端會以 400/403 回應。
    await _client.sendJson('POST', '/api/users/password', body: {
      'user_id': userId,
      'new_password': newPassword,
    });
  }
}
