import 'package:flutter/material.dart';
import '../../../data/models/component_model.dart';
import 'framed_component_tile.dart';

/// 原料介紹頁（參考 3_conponent_detail）：
/// 左側為原料卡框大圖 + 名稱；右側上方為介紹文字、下方為實景參考照。
/// 內容浮在變暗的背景上，右上角為關閉鈕。
class ComponentDetailDialog extends StatelessWidget {
  final ComponentModel component;
  final int quantity;

  const ComponentDetailDialog({
    super.key,
    required this.component,
    required this.quantity,
  });

  static const double _cardW = 240;
  static const double _cardH = 360;

  static const _levelColor = {
    1: Color(0xFF6FBF73),
    2: Color(0xFFE3B341),
    3: Color(0xFFD9534F),
  };

  @override
  Widget build(BuildContext context) {
    final color = _levelColor[component.level] ?? Colors.white;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leftCard(color),
            const SizedBox(width: 28),
            Expanded(child: _rightColumn(context)),
          ],
        ),
      ),
    );
  }

  // ── 左：卡框大圖 + 名稱 ──────────────────────────────────────────────────────
  Widget _leftCard(Color color) {
    return Container(
      width: _cardW,
      height: _cardH,
      decoration: BoxDecoration(
        color: const Color(0xF223262A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      child: Column(
        children: [
          Expanded(child: FramedComponentTile(component: component)),
          const SizedBox(height: 14),
          Text(
            component.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF3E7CE),
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ── 右：關閉鈕 + 介紹文字 + 參考照 ──────────────────────────────────────────
  Widget _rightColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _closeButton(context),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: SingleChildScrollView(
            child: Text(
              component.description.isNotEmpty
                  ? component.description
                  : '簡介尚未開放，敬請期待。',
              style: const TextStyle(
                color: Color(0xFFE9E3D8),
                fontSize: 16,
                height: 1.9,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _photoRow(),
      ],
    );
  }

  Widget _closeButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xCC4A4D50),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _photoRow() {
    final photos = component.referencePhotos;
    final tiles = photos.isNotEmpty
        ? photos.take(3).map(_photoTile).toList()
        : [_photoPlaceholder(), _photoPlaceholder()];
    return SizedBox(
      height: 150,
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }

  Widget _photoTile(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _photoPlaceholder(),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3D40), Color(0xFF24272A)],
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24, size: 34),
      ),
    );
  }
}
