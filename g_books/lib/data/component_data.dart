import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'models/component_model.dart';
import 'models/heritage_config.dart';
import 'map_cell_data.dart';
import 'slot_data.dart';

/// 原料資料改為「設定驅動」：
/// - 「有哪些原料」由 assets 內的圖片決定（`components/<id>.png`，[loadComponentImageIds]）。
/// - 每個原料的名稱 / 等級由 [ComponentMeta]（管理者可編輯）提供。
/// - 可放哪些 slot 由 component_slots 設定提供。
///
/// 三者透過 [applyHeritageConfig] 套用後組成對外的 [ComponentModel] 清單，
/// 學生端 [componentsOf] / [componentById] 照常運作、簽名不變。

// 各古蹟可用的原料圖片 id（讀 AssetManifest，啟動載入一次）。
final Map<String, List<int>> _imageIdsByHeritage = {};
// 套用後的中繼資料 / 可放 slot。
final Map<String, Map<int, ComponentMeta>> _metaByHeritage = {};
final Map<String, Map<int, Set<int>>> _slotsByComponent = {};
// 組好的對外清單。
final Map<String, List<ComponentModel>> _componentsByHeritage = {};

List<int> componentImageIdsOf(String heritageId) =>
    _imageIdsByHeritage[heritageId] ?? const [];

List<ComponentModel> componentsOf(String heritageId) =>
    _componentsByHeritage[heritageId] ?? const [];

ComponentModel? componentById(String heritageId, int id) {
  for (final c in componentsOf(heritageId)) {
    if (c.id == id) return c;
  }
  return null;
}

/// 該古蹟指定等級（1~3）的全部原料，供資源採集「依難度給對應等級獎勵」挑選。
List<ComponentModel> componentsByLevel(String heritageId, int level) =>
    [for (final c in componentsOf(heritageId)) if (c.level == level) c];

/// 啟動時讀 AssetManifest，列出每座古蹟 `components/<id>.png` 的 id 清單。
///
/// **只收正整數 id**：負數圖（`-<id>.png`）是該原料「損毀狀態」的替身圖，由
/// [ComponentModel.brokenImagePath] 依正 id 推導，**不是另一個原料**——不可進入原料
/// 清單，否則會混入背包 / 原料庫 / 採集難度池 / 管理者物品設定與後端 difficulty_type。
Future<void> loadComponentImageIds(Iterable<String> heritageIds) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest.listAssets();
  for (final hid in heritageIds) {
    final prefix = 'assets/heritages/$hid/components/';
    final ids = <int>[];
    for (final a in assets) {
      if (a.startsWith(prefix) && a.endsWith('.png')) {
        final base = a.substring(prefix.length, a.length - 4);
        final id = int.tryParse(base);
        // 負數 / 0 是損毀替身圖，略過；只有正 id 才是可採集原料。
        if (id != null && id > 0) ids.add(id);
      }
    }
    ids.sort();
    _imageIdsByHeritage[hid] = ids;
  }
}

/// 套用某古蹟設定（啟動種子化 / 管理者儲存後即時生效）。
void applyHeritageConfig(String heritageId, HeritageConfig config) {
  _metaByHeritage[heritageId] = config.components;
  _slotsByComponent[heritageId] = config.componentSlots;
  setHeritageSlots(heritageId, config.slots);
  setHeritageMapCells(heritageId, config.mapCells);
  _rebuild(heritageId);
}

void _rebuild(String heritageId) {
  final ids = _imageIdsByHeritage[heritageId] ?? const [];
  final meta = _metaByHeritage[heritageId] ?? const {};
  final slots = _slotsByComponent[heritageId] ?? const {};
  _componentsByHeritage[heritageId] = [
    for (final id in ids)
      ComponentModel(
        id: id,
        heritageId: heritageId,
        name: (meta[id]?.name.isNotEmpty ?? false) ? meta[id]!.name : '原料$id',
        level: meta[id]?.level ?? 1,
        allowedSlotIds: slots[id] ?? const {},
      ),
  ];
}
