import '../data/mock_data.dart';
import '../data/models/staff_account.dart';
import 'api_client.dart';

/// 管理者後台「教師帳號管理」看到的一筆老師帳號（user role=1）。
/// 小組帳號（role=0）由教師控制台管理、管理者（role=2）不出現在此清單。
class TeacherAccount {
  final String username;
  final String? avatarUrl;
  const TeacherAccount({required this.username, this.avatarUrl});
}

/// 管理者對「教師帳號」的後端操作抽象層。只管 role=1（老師）；不碰小組帳號。
///
/// 對應 `gb_api` 端點：
///   - [listTeachers]         ↔ `GET /api/users`（取 role=1）
///   - [createTeacher]        ↔ `POST /api/register`（role=1）
///   - [deleteTeacher]        ↔ `DELETE /api/users/{username}`
///   - [resetTeacherPassword] ↔ `POST /api/users/password`（**待後端開放**：
///       目前該端點只能改「自己」且要驗舊密碼；需比照 `SetProfilePic` 改成可帶
///       目標 `username`、且 teacher/admin 改他人時略過舊密碼驗證。後端補上前會回錯誤。)
///
/// Mock 版操作本機資料；換真後端只要在 `main.dart` 改用 [ApiAccountService]，UI 不變。
abstract class AccountService {
  Future<List<TeacherAccount>> listTeachers();

  /// 建立老師帳號（role=1）。帳號已存在時拋例外（後端回 409）。
  Future<void> createTeacher(
      {required String username, required String password});

  /// 刪除一個老師帳號。
  Future<void> deleteTeacher({required String username});

  /// 重設某老師的密碼（管理者免舊密碼）。**需後端開放**，未開放前會拋例外。
  Future<void> resetTeacherPassword(
      {required String username, required String newPassword});
}

/// 本機 mock：教師帳號從 [mockStaff] 的 teacher 角色種子化，密碼存在本機可變 map。
class MockAccountService implements AccountService {
  MockAccountService() {
    for (final s in mockStaff) {
      if (s.role == StaffRole.teacher) {
        _teachers.add(s.username);
        _passwords[s.username] = s.password;
      }
    }
  }

  final List<String> _teachers = [];
  final Map<String, String> _passwords = {};

  @override
  Future<List<TeacherAccount>> listTeachers() async {
    final list = List<String>.from(_teachers)..sort();
    return [for (final u in list) TeacherAccount(username: u)];
  }

  @override
  Future<void> createTeacher(
      {required String username, required String password}) async {
    if (_teachers.contains(username)) {
      throw Exception('帳號 $username 已存在');
    }
    _teachers.add(username);
    _passwords[username] = password;
  }

  @override
  Future<void> deleteTeacher({required String username}) async {
    _teachers.remove(username);
    _passwords.remove(username);
  }

  @override
  Future<void> resetTeacherPassword(
      {required String username, required String newPassword}) async {
    if (!_teachers.contains(username)) throw Exception('帳號 $username 不存在');
    _passwords[username] = newPassword;
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
  Future<void> deleteTeacher({required String username}) async {
    await _client.sendJson(
        'DELETE', '/api/users/${Uri.encodeComponent(username)}');
  }

  @override
  Future<void> resetTeacherPassword(
      {required String username, required String newPassword}) async {
    // 帶目標 username + 新密碼（不帶舊密碼）。後端比照 SetProfilePic 開放
    // 「teacher/admin 改他人」後即生效；未開放前後端會以 400/403 回應。
    await _client.sendJson('POST', '/api/users/password', body: {
      'username': username,
      'new_password': newPassword,
    });
  }
}
