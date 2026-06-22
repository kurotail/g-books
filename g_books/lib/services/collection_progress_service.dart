import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 資源採集進度：記錄「某採集場次（以 組別 + 該階段開始時間 辨識）進行到第幾回合」。
/// 讓使用者中途跳出 App / 換組登入後再回到採集，能各自接續對應回合
/// （回合本身為本機進度、不串後端）。
class CollectionProgress {
  /// 場次識別：`組別id:採集階段開始時間(ISO8601)`。換組或換場次即視為不同進度。
  final String sessionKey;
  final int round;

  const CollectionProgress({required this.sessionKey, required this.round});
}

/// 採集進度的持久化來源抽象層；現以本機檔案實作，之後可改由後端記錄每組進度。
abstract class CollectionProgressService {
  /// 讀取指定場次的進度；無則回 null。
  Future<CollectionProgress?> load(String sessionKey);

  /// 寫入 / 更新指定場次的進度。
  Future<void> save(CollectionProgress progress);

  Future<void> clear();
}

/// 本機實作：寫 App 文件區的單一 JSON 檔，內含「多場次」進度
/// （以 sessionKey 區分），避免不同組在同一台裝置互相覆蓋彼此的回合。
class LocalCollectionProgressService implements CollectionProgressService {
  /// 同檔保留的最多場次數（最近使用者優先；超過則汰除最舊）。
  static const int _maxEntries = 24;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gb_collection_progress.json');
  }

  /// 讀出全部場次進度（newest last）；相容舊版單筆格式。
  Future<List<CollectionProgress>> _readAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, dynamic>) {
        final items = decoded['items'];
        if (items is List) {
          final out = <CollectionProgress>[];
          for (final e in items) {
            if (e is Map) {
              final key = e['sessionKey'] as String?;
              final round = (e['round'] as num?)?.toInt();
              if (key != null && round != null) {
                out.add(CollectionProgress(sessionKey: key, round: round));
              }
            }
          }
          return out;
        }
        // 舊版單筆格式 {sessionKey, round}。
        final key = decoded['sessionKey'] as String?;
        final round = (decoded['round'] as num?)?.toInt();
        if (key != null && round != null) {
          return [CollectionProgress(sessionKey: key, round: round)];
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<CollectionProgress?> load(String sessionKey) async {
    final all = await _readAll();
    for (final p in all) {
      if (p.sessionKey == sessionKey) return p;
    }
    return null;
  }

  @override
  Future<void> save(CollectionProgress p) async {
    try {
      final all = await _readAll()
        ..removeWhere((e) => e.sessionKey == p.sessionKey)
        ..add(p); // 移到最後＝最近使用。
      // 汰除最舊，控制檔案大小。
      final trimmed = all.length > _maxEntries
          ? all.sublist(all.length - _maxEntries)
          : all;
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'items': [
            for (final e in trimmed)
              {'sessionKey': e.sessionKey, 'round': e.round},
          ],
        }),
      );
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
