/// 古蹟上的一個放置位置（slot）。
///
/// 座標一律以 **main.png 為基準的正規化值（0~1）**儲存，與螢幕解析度、
/// 縮放倍率無關：
///   - [cx], [cy]：slot 中心點，相對 main.png 寬/高的比例（0=左/上，1=右/下）
///   - [w], [h]  ：slot 寬/高，相對 main.png 寬/高的比例
///
/// 如此一來，無論 main.png 在畫面上被等比例縮放或 InteractiveViewer 拖曳放大，
/// 只要把這些比例乘上 main.png 當下的顯示矩形即可得到實際位置，slot 與其上的
/// 原料就會跟著 main 一起變大變小、一起移動。
class HeritageSlot {
  final int id;
  final double cx;
  final double cy;
  final double w;
  final double h;

  const HeritageSlot({
    required this.id,
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });

  HeritageSlot copyWith({double? cx, double? cy, double? w, double? h}) =>
      HeritageSlot(
        id: id,
        cx: cx ?? this.cx,
        cy: cy ?? this.cy,
        w: w ?? this.w,
        h: h ?? this.h,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cx': _round(cx),
        'cy': _round(cy),
        'w': _round(w),
        'h': _round(h),
      };

  factory HeritageSlot.fromJson(Map<String, dynamic> json) => HeritageSlot(
        id: (json['id'] as num).toInt(),
        cx: (json['cx'] as num).toDouble(),
        cy: (json['cy'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}
