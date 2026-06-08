/// 古蹟原料（component）。採集成功後進入背包，於編輯古蹟拖曳到對應 slot。
///
/// 由設定（[componentsOf] 組裝）產生：圖片(由 [heritageId]+[id] 推導) - id -
/// 名稱/等級([level]，可由管理者編輯) - 可放置 slot([allowedSlotIds])。
/// 原料的詳細圖文介紹改由 `assets/data/heritages/<hid>/components/<id>.md` 提供。
class ComponentModel {
  /// 對應 `components/<id>.png`。
  final int id;

  /// 所屬古蹟 id，用來組出圖片路徑。
  final String heritageId;

  final String name;

  /// 等級 1~3，決定卡框顏色（綠/黃/紅）。
  final int level;

  /// 此原料可放置的 slot id 清單（一個原料可放多個指定 slot）。
  final Set<int> allowedSlotIds;

  const ComponentModel({
    required this.id,
    required this.heritageId,
    required this.name,
    required this.level,
    this.allowedSlotIds = const {},
  });

  /// 原料圖片路徑。
  String get imagePath =>
      'assets/images/heritages/$heritageId/components/$id.png';

  /// 依等級取得卡框圖。
  String get frameImagePath => levelFrameImagePath(level);

  bool canPlaceIn(int slotId) => allowedSlotIds.contains(slotId);
}

/// 等級 → 卡框圖。lv1 綠、lv2 黃、lv3 紅。
String levelFrameImagePath(int level) => switch (level) {
      1 => 'assets/icons/card_frames/green.png',
      2 => 'assets/icons/card_frames/yellow.png',
      _ => 'assets/icons/card_frames/red.png',
    };
