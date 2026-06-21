import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 教師「上課場次」的本機持久化（純前端、單一裝置）。
///
/// 「開始上課」目前不是後端狀態（後端 `/api/state` 只存遊戲階段，上課中大多停在平時），
/// 因此把「某位老師開了一場、尚未結束的課」記在本機，讓老師登出 / 被踢 / 重開 App 後
/// 重登時，能直接回到「課程控制（遊戲階段）」頁，而不是退回課前準備。
///
/// 以 username 當鍵：同一台裝置換另一位老師登入時不會誤判成上課中。整檔只記目前持有
/// 上課場次的帳號，[end] 直接刪檔。任何 IO 失敗都安靜吞掉（最差只是回不到上課頁）。
class CourseSessionStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gb_course_session.json');
  }

  /// 目前是否有「由 [username] 開始且尚未結束」的上課場次。
  Future<bool> isActiveFor(String username) async {
    if (username.isEmpty) return false;
    try {
      final f = await _file();
      if (!await f.exists()) return false;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (m['username'] as String?) == username;
    } catch (_) {
      return false;
    }
  }

  /// 記下 [username] 開始了一場課（覆蓋既有）。
  Future<void> start(String username) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({'username': username}));
    } catch (_) {}
  }

  /// 結束課程：清掉本機場次。
  Future<void> end() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
