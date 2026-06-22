import 'heritage_slot.dart';

/// 單一原料的可編輯中繼資料（名稱、等級）。圖片與「可放哪些 slot」另外保存。
class ComponentMeta {
  String name;
  int level; // 1~3

  ComponentMeta({required this.name, required this.level});

  factory ComponentMeta.fromJson(Map<String, dynamic> j) => ComponentMeta(
        name: (j['name'] as String?) ?? '',
        level: (j['level'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {'name': name, 'level': level};

  ComponentMeta copy() => ComponentMeta(name: name, level: level);
}

/// 一座古蹟的完整可編輯設定，對應假後端回傳 / 儲存的 JSON：
/// - [slots]          ↔ `slots.json`（陣列；slot 幾何）
/// - [componentSlots] ↔ `component_slots.json`（`{cid:[slotId...]}`）
/// - [components]     ↔ `components.json`（`{cid:{name,level}}`）
/// - [mapCells]       ↔ `map_cells.json`（陣列；攻防戰世界地圖島格幾何，正規化於
///                       fight_map.png）。各組島嶼依序填入這些格子。
///
/// 空設定即各項皆空（對應後端回傳 `[]` / `{}`）。
class HeritageConfig {
  final List<HeritageSlot> slots;
  final Map<int, Set<int>> componentSlots;
  final Map<int, ComponentMeta> components;

  /// 攻防戰世界地圖的島格（沿用 [HeritageSlot] 的 cx/cy/w/h，但座標基準是
  /// fight_map.png 的顯示矩形，而非 main.png）。管理者在「世界地圖」模式擺放。
  final List<HeritageSlot> mapCells;

  HeritageConfig({
    this.slots = const [],
    Map<int, Set<int>>? componentSlots,
    Map<int, ComponentMeta>? components,
    this.mapCells = const [],
  })  : componentSlots = componentSlots ?? {},
        components = components ?? {};
}
