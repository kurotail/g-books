import 'package:flutter/widgets.dart';
import '../../data/models/heritage_slot.dart';

/// 古蹟檢視/編輯共用的版面幾何。
///
/// 場景結構：bg_view.png 鋪滿 viewport（cover），main.png 置中為正方形，
/// 邊長 = viewport 寬 × [mainSizeFraction]。slot 座標為 main.png 正規化值，
/// 乘上 main 的顯示矩形即得實際位置。這些計算都在 InteractiveViewer 的 child
/// 座標空間內進行，因此會隨縮放/平移一起變換。
class HeritageViewGeometry {
  HeritageViewGeometry._();

  /// main.png 顯示邊長相對 viewport 寬的比例（可調）。
  static const double mainSizeFraction = 0.65;

  /// main.png 在 [viewport] 內的置中正方形矩形。
  static Rect mainRect(Size viewport) {
    final size = viewport.width * mainSizeFraction;
    final left = (viewport.width - size) / 2;
    final top = (viewport.height - size) / 2;
    return Rect.fromLTWH(left, top, size, size);
  }

  /// 依 main 顯示矩形 [main]，換算某 slot 的實際矩形。
  static Rect slotRect(HeritageSlot s, Rect main) => Rect.fromCenter(
        center: Offset(
          main.left + s.cx * main.width,
          main.top + s.cy * main.height,
        ),
        width: s.w * main.width,
        height: s.h * main.height,
      );
}
