import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../../data/models/heritage_slot.dart';

/// 攻防戰世界地圖的版面幾何（攻防戰畫面與管理者「世界地圖」編輯器共用）。
///
/// 場景結構：bg_fight.png 為固定全螢幕底圖（不隨縮放，畫在 InteractiveViewer 之外）；
/// fight_map.png 為主島，置中、依原圖長寬比顯示，邊寬 = viewport 寬 × [mainWidthFraction]；
/// supply_station.png 為補給島，浮在主島右上方。各組島格座標為 fight_map.png 顯示矩形的
/// 正規化值（cx/cy/w/h），乘上主島顯示矩形即得實際位置——與 slot 對 main.png 的關係一致。
class FightMapGeometry {
  FightMapGeometry._();

  /// fight_map.png 原圖長寬比（1102 × 996）。
  static const double mainAspect = 1102 / 996;

  /// supply_station.png 原圖長寬比（834 × 556）。
  static const double supplyAspect = 834 / 556;

  /// 主島顯示寬相對 viewport 寬的比例。
  static const double mainWidthFraction = 0.82;

  /// 主島（fight_map.png）在 [viewport] 內的置中矩形（依原圖長寬比）。
  static Rect mainRect(Size viewport) {
    final w = viewport.width * mainWidthFraction;
    final h = w / mainAspect;
    return Rect.fromCenter(
      center: Offset(viewport.width * 0.5, viewport.height * 0.55),
      width: w,
      height: h,
    );
  }

  /// 依主島矩形 [main]，換算某島格（[c]）的實際矩形。
  static Rect cellRect(HeritageSlot c, Rect main) => Rect.fromCenter(
        center: Offset(
          main.left + c.cx * main.width,
          main.top + c.cy * main.height,
        ),
        width: c.w * main.width,
        height: c.h * main.height,
      );

  /// 補給島（supply_station.png）矩形：浮在主島右上方。
  static Rect supplyRect(Rect main) {
    final w = main.width * 0.30;
    final h = w / supplyAspect;
    return Rect.fromCenter(
      center: Offset(main.right + w * 0.05, main.top - h * 0.05),
      width: w,
      height: h,
    );
  }

  /// 島格內實際擺放島嶼圖（main/enemy.png 為正方形）的最大置中正方形，
  /// 讓島上元件能依正方形對齊、不因島格長寬比不同而變形。
  static Rect islandSquare(Rect cell) {
    final side = math.min(cell.width, cell.height);
    return Rect.fromCenter(center: cell.center, width: side, height: side);
  }
}
