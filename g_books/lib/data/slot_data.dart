import 'models/heritage_slot.dart';

/// 各古蹟的 slot 幾何（main.png 正規化座標）。內容由設定服務於啟動種子化、
/// 或管理者儲存後，透過 [setHeritageSlots] 套用（見 `applyHeritageConfig`）。
final Map<String, List<HeritageSlot>> _slotsByHeritage = {};

List<HeritageSlot> slotsOf(String heritageId) =>
    _slotsByHeritage[heritageId] ?? const [];

/// 套用某古蹟的 slot 幾何（啟動種子化 / 管理者儲存後即時生效）。
void setHeritageSlots(String heritageId, List<HeritageSlot> slots) {
  _slotsByHeritage[heritageId] = List<HeritageSlot>.from(slots);
}
