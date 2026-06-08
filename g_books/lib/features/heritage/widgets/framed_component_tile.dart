import 'package:flutter/material.dart';
import '../../../data/models/component_model.dart';

/// 原料「卡框圖磚」：填滿給定區域，由下往上疊 —— 米色圓角底（可選）、等級卡框、
/// 原料圖（依寬度等比例內縮，底部多留白避開卡框的橫飾條），右下角可選數量徽章。
///
/// 背包物品卡與原料介紹框（InfoDialog 左側 leading）共用此視覺，
/// 比例以容器寬度為基準，因此同一份係數可同時還原兩處（150 寬背包卡、190 寬介紹卡）。
class FramedComponentTile extends StatelessWidget {
  final ComponentModel component;

  /// null = 不顯示數量徽章。
  final int? quantity;

  /// 是否鋪米色圓角底。
  final bool tanBackground;

  /// 物品卡底色（暖米色）。
  static const Color tan = Color(0xFFDBC0A4);

  const FramedComponentTile({
    super.key,
    required this.component,
    this.quantity,
    this.tanBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        return Stack(
          children: [
            // 米色圓角底（內縮 7%，四角藏進卡框邊飾下）。
            if (tanBackground)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(w * 0.07),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tan,
                      borderRadius: BorderRadius.circular(w * 0.12),
                    ),
                  ),
                ),
              ),
            // 等級卡框（外框）。
            Positioned.fill(
              child: Image.asset(
                component.frameImagePath,
                fit: BoxFit.fill,
                errorBuilder: (_, _, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            // 原料圖（底部多留白避開卡框底部的橫飾條）。
            Padding(
              padding: EdgeInsets.fromLTRB(
                w * 0.17,
                w * 0.14,
                w * 0.17,
                w * 0.22,
              ),
              child: Image.asset(
                component.imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.image_not_supported,
                  color: Colors.white24,
                ),
              ),
            ),
            if (quantity != null)
              Positioned(right: 6, bottom: 6, child: _qtyBadge(quantity!)),
          ],
        );
      },
    );
  }

  Widget _qtyBadge(int qty) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white54),
    ),
    child: Text(
      '×$qty',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
