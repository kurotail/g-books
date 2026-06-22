import 'models/heritage_slot.dart';

/// 各古蹟「攻防戰世界地圖島格」的幾何（fight_map.png 正規化座標）。
///
/// 與 slot_data 平行：內容由設定服務於啟動種子化、或管理者在編輯器「世界地圖」模式
/// 儲存後，透過 [setHeritageMapCells] 套用（見 `applyHeritageConfig`）。攻防戰畫面以
/// [mapCellsOf] 取得各組島嶼要落在世界地圖的哪些格子。
final Map<String, List<HeritageSlot>> _cellsByHeritage = {};

List<HeritageSlot> mapCellsOf(String heritageId) =>
    _cellsByHeritage[heritageId] ?? const [];

/// 套用某古蹟的世界地圖島格（啟動種子化 / 管理者儲存後即時生效）。
void setHeritageMapCells(String heritageId, List<HeritageSlot> cells) {
  _cellsByHeritage[heritageId] = List<HeritageSlot>.from(cells);
}
