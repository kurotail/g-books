import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'models/component_model.dart';

/// 各古蹟的原料**基礎**清單（名稱 / 等級 / 介紹），key = heritageId。
///
/// 目前僅北港朝天宮有素材（`conponents/1.png`~`12.png`）。
///
/// 「原料可放哪些 slot」(allowedSlotIds) 改由 Slot 編輯器的「原料對應」模式編輯，
/// 輸出成 `assets/data/component_slots/<heritageId>.json`，於啟動時由
/// [loadComponentSlots] 載入並覆蓋下列基礎清單的 allowedSlotIds。
/// ⚠️ [ComponentModel.description] 仍為**佔位文案**，最終內容待需求方提供。
const Map<String, List<ComponentModel>> _baseComponentsByHeritage = {
  'beigang_chaotian_temple': _beigangComponents,
};

/// 啟動後實際使用的原料清單（已套用 allowedSlots 覆蓋）。
final Map<String, List<ComponentModel>> _componentsByHeritage = {};

List<ComponentModel> componentsOf(String heritageId) =>
    _componentsByHeritage[heritageId] ??
    _baseComponentsByHeritage[heritageId] ??
    const [];

ComponentModel? componentById(String heritageId, int id) {
  for (final c in componentsOf(heritageId)) {
    if (c.id == id) return c;
  }
  return null;
}

/// 載入各古蹟的「原料 → 可放 slot」對應 JSON（缺檔則沿用基礎清單的預設值）。
/// 檔案格式：`{ "<componentId>": [slotId, ...], ... }`
Future<void> loadComponentSlots(Iterable<String> heritageIds) async {
  for (final hid in heritageIds) {
    final base = _baseComponentsByHeritage[hid];
    if (base == null) continue;

    Map<String, dynamic>? override;
    try {
      final raw = await rootBundle
          .loadString('assets/data/component_slots/$hid.json');
      override = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      override = null;
    }

    _componentsByHeritage[hid] = base.map((c) {
      final entry = override?['${c.id}'];
      if (entry is List) {
        return c.copyWith(
          allowedSlotIds: entry.map((e) => (e as num).toInt()).toSet(),
        );
      }
      return c;
    }).toList();
  }
}

const _hid = 'beigang_chaotian_temple';

const List<ComponentModel> _beigangComponents = [
  // ── Lv1 ────────────────────────────────────────────────────────────────────
  ComponentModel(
    id: 1,
    heritageId: _hid,
    name: '門釘廟門',
    level: 1,
    allowedSlotIds: {1},
    description: '廟門上的門釘排列象徵尊貴與守護，是進入廟埕的第一道門面。（簡介待補）',
  ),
  ComponentModel(
    id: 2,
    heritageId: _hid,
    name: '華麗獅',
    level: 1,
    allowedSlotIds: {2, 3},
    description: '成對的石獅鎮守廟門兩側，象徵驅邪納福。（簡介待補）',
  ),
  ComponentModel(
    id: 3,
    heritageId: _hid,
    name: '燈籠',
    level: 1,
    allowedSlotIds: {4, 5},
    description: '高懸的燈籠照亮廟埕，於慶典時更添莊嚴氣氛。（簡介待補）',
  ),
  ComponentModel(
    id: 4,
    heritageId: _hid,
    name: '石燈',
    level: 1,
    allowedSlotIds: {6},
    description: '石造燈座立於庭院，兼具照明與裝飾。（簡介待補）',
  ),
  // ── Lv2 ────────────────────────────────────────────────────────────────────
  ComponentModel(
    id: 5,
    heritageId: _hid,
    name: '戲檯',
    level: 2,
    allowedSlotIds: {7},
    description: '酬神演戲的舞台，是傳統廟會的重要場域。（簡介待補）',
  ),
  ComponentModel(
    id: 6,
    heritageId: _hid,
    name: '晨鐘樓',
    level: 2,
    allowedSlotIds: {8},
    description: '晨間鳴鐘以報時、聚眾，與暮鼓樓相對而立。（簡介待補）',
  ),
  ComponentModel(
    id: 7,
    heritageId: _hid,
    name: '香爐',
    level: 2,
    allowedSlotIds: {9},
    description: '信眾上香祈福之處，終年香火鼎盛。（簡介待補）',
  ),
  ComponentModel(
    id: 8,
    heritageId: _hid,
    name: '暮鼓樓',
    level: 2,
    allowedSlotIds: {10},
    description: '黃昏擊鼓示警報時，與晨鐘樓構成「晨鐘暮鼓」。（簡介待補）',
  ),
  // ── Lv3 ────────────────────────────────────────────────────────────────────
  ComponentModel(
    id: 9,
    heritageId: _hid,
    name: '交趾陶_1',
    level: 3,
    allowedSlotIds: {11},
    description: '色彩斑斕的交趾陶為台灣寺廟代表性裝飾工藝。（簡介待補）',
  ),
  ComponentModel(
    id: 10,
    heritageId: _hid,
    name: '火珠雕塑',
    level: 3,
    allowedSlotIds: {12},
    description: '屋脊中央的火珠，兩側常配龍形，象徵祥瑞。（簡介待補）',
  ),
  ComponentModel(
    id: 11,
    heritageId: _hid,
    name: '福祿壽',
    level: 3,
    allowedSlotIds: {13},
    description: '福、祿、壽三仙塑像，寄寓對美好生活的祈願。（簡介待補）',
  ),
  ComponentModel(
    id: 12,
    heritageId: _hid,
    name: '交趾陶_2',
    level: 3,
    allowedSlotIds: {14},
    description: '另一組交趾陶作品，題材多取自民間故事。（簡介待補）',
  ),
];
