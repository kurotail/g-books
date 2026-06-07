import 'package:flutter/material.dart';
import '../../../data/models/component_model.dart';

/// 原料卡片：等級卡框 + 原料圖，可選顯示數量徽章與名稱。
/// 數量為 0 時以灰階 + 半透明呈現（原料庫顯示未擁有原料）。
class ComponentCard extends StatelessWidget {
  final ComponentModel component;
  final double size;

  /// null = 不顯示數量徽章。
  final int? quantity;

  final bool showName;

  const ComponentCard({
    super.key,
    required this.component,
    this.size = 88,
    this.quantity,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    final owned = quantity == null || quantity! > 0;

    Widget image = Image.asset(
      component.imagePath,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.image_not_supported, color: Colors.white24),
    );
    if (!owned) {
      // 灰階 + 變暗，表示尚未擁有。
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 1, 0, //
        ]),
        child: Opacity(opacity: 0.55, child: image),
      );
    }

    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                // 卡框
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
                // 原料圖（內縮，避免蓋住卡框）
                Padding(
                  padding: EdgeInsets.all(size * 0.16),
                  child: image,
                ),
                // 數量徽章
                if (quantity != null)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: owned ? Colors.black87 : Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: owned ? Colors.white54 : Colors.white24,
                        ),
                      ),
                      child: Text(
                        '×$quantity',
                        style: TextStyle(
                          color: owned ? Colors.white : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showName) ...[
            const SizedBox(height: 4),
            Text(
              component.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: owned ? Colors.white : Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
