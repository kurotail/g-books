import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 資源採集進度：記錄「目前採集場次（以該階段開始時間辨識）進行到第幾回合」。
/// 讓使用者中途跳出 App、重啟後回到採集能接續對應回合（回合本身為本機進度、不串後端）。
class CollectionProgress {
  /// 場次識別：採集階段的開始時間（ISO8601）。換場次（開始時間不同）即視為新進度。
  final String sessionKey;
  final int round;

  const CollectionProgress({required this.sessionKey, required this.round});
}

/// 採集進度的持久化來源抽象層；現以本機檔案實作，之後可改由後端記錄每組進度。
abstract class CollectionProgressService {
  Future<CollectionProgress?> load();
  Future<void> save(CollectionProgress progress);
  Future<void> clear();
}

/// 本機實作：寫 App 文件區的單一 JSON 檔。
class LocalCollectionProgressService implements CollectionProgressService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gb_collection_progress.json');
  }

  @override
  Future<CollectionProgress?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final key = m['sessionKey'] as String?;
      final round = (m['round'] as num?)?.toInt();
      if (key == null || round == null) return null;
      return CollectionProgress(sessionKey: key, round: round);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CollectionProgress p) async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({'sessionKey': p.sessionKey, 'round': p.round}),
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
