import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'models/heritage_slot.dart';

/// 各古蹟的 slot 幾何，每個古蹟一個 JSON 檔：
///   `assets/data/slots/<heritageId>.json`
///
/// 檔案內容為 slot 陣列（即 Slot 編輯器「輸出 JSON」的結果），座標皆為 main.png
/// 正規化值（見 [HeritageSlot]）。於 App 啟動時由 [loadHeritageSlots] 一次載入。
///
/// 新增一座古蹟 → 只要：
///   1. 用 Slot 編輯器排好位置、輸出 JSON
///   2. 存成 `assets/data/slots/<新古蹟id>.json`
///   3. 該古蹟的原料加進 `component_data.dart`
/// 不需改任何程式碼。
final Map<String, List<HeritageSlot>> _slotsByHeritage = {};

List<HeritageSlot> slotsOf(String heritageId) =>
    _slotsByHeritage[heritageId] ?? const [];

HeritageSlot? slotById(String heritageId, int id) {
  for (final s in slotsOf(heritageId)) {
    if (s.id == id) return s;
  }
  return null;
}

/// 啟動時載入指定古蹟的 slot 幾何。缺檔（尚未排版的古蹟）會被略過。
Future<void> loadHeritageSlots(Iterable<String> heritageIds) async {
  for (final id in heritageIds) {
    try {
      final raw = await rootBundle.loadString('assets/data/slots/$id.json');
      final list = (jsonDecode(raw) as List)
          .map((e) => HeritageSlot.fromJson(e as Map<String, dynamic>))
          .toList();
      _slotsByHeritage[id] = list;
    } catch (_) {
      // 該古蹟尚無 slot 檔，略過。
    }
  }
}
