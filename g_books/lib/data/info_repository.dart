import 'package:flutter/services.dart' show rootBundle;
import 'models/info_section.dart';

/// 載入各古蹟的圖文資訊（Markdown）並快取。
///
/// 檔案位置：
/// - 古蹟介紹：`assets/data/heritages/<hid>/heritage.md`
/// - 各原料： `assets/data/heritages/<hid>/components/<cid>.md`
///
/// 兩者都被解析成相同的 [InfoSection] 清單（以 `# 標題` 分頁），由統一的 InfoDialog 渲染。
class InfoRepository {
  InfoRepository._();

  static final Map<String, List<InfoSection>> _cache = {};

  /// 古蹟資訊圖片的根目錄；md 內 `![](檔名)` 會以此為前綴解析。
  static String imageBaseDir(String heritageId) =>
      'assets/images/heritages/$heritageId/info/';

  static Future<List<InfoSection>> _load(String key, String assetPath) async {
    final cached = _cache[key];
    if (cached != null) return cached;

    List<InfoSection> sections;
    try {
      final raw = await rootBundle.loadString(assetPath);
      sections = parseInfoSections(raw);
    } catch (_) {
      // 缺檔或解析失敗：給一個佔位分頁，畫面仍可開啟。
      sections = const [
        InfoSection(tab: '簡介', markdown: '資訊尚未開放，敬請期待。'),
      ];
    }
    _cache[key] = sections;
    return sections;
  }

  /// 古蹟本身的介紹（選擇古蹟頁與古蹟檢視頁共用）。
  static Future<List<InfoSection>> heritage(String heritageId) => _load(
        'h:$heritageId',
        'assets/data/heritages/$heritageId/heritage.md',
      );

  /// 單一原料的介紹（由原料庫圖鑑點卡片進入）。
  static Future<List<InfoSection>> component(String heritageId, int componentId) =>
      _load(
        'c:$heritageId/$componentId',
        'assets/data/heritages/$heritageId/components/$componentId.md',
      );
}
