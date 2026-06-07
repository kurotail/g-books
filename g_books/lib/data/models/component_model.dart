/// 古蹟原料（component）。採集成功後進入背包，於編輯古蹟拖曳到對應 slot。
///
/// 統一儲存：圖片(由 [heritageId]+[id] 推導) - id - 等級([level]) - 可放置 slot
/// ([allowedSlotIds]) - 名稱/介紹（供原料庫圖鑑顯示）。
class ComponentModel {
  /// 1..12，對應 `conponents/<id>.png`（注意資料夾為既有拼字 "conponents"）。
  final int id;

  /// 所屬古蹟 id，用來組出圖片路徑。
  final String heritageId;

  final String name;

  /// 等級 1~3，決定卡框顏色（綠/黃/紅）。
  final int level;

  /// 此原料可放置的 slot id 清單（一個原料可放多個指定 slot）。
  final Set<int> allowedSlotIds;

  /// 原料庫圖鑑用的詳細介紹文字。
  final String description;

  /// 原料介紹頁的實景參考照（asset 路徑）。尚無素材時留空，詳情頁會以佔位圖呈現。
  final List<String> referencePhotos;

  const ComponentModel({
    required this.id,
    required this.heritageId,
    required this.name,
    required this.level,
    required this.allowedSlotIds,
    this.description = '',
    this.referencePhotos = const [],
  });

  ComponentModel copyWith({Set<int>? allowedSlotIds}) => ComponentModel(
        id: id,
        heritageId: heritageId,
        name: name,
        level: level,
        allowedSlotIds: allowedSlotIds ?? this.allowedSlotIds,
        description: description,
        referencePhotos: referencePhotos,
      );

  /// 原料圖片路徑。
  String get imagePath =>
      'assets/images/heritages/$heritageId/conponents/$id.png';

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
