import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AvatarFrame extends StatelessWidget {
  final double size;

  /// 遠端 URL（https://...）或本地路徑，null 顯示預設人像
  final String? imageUrl;

  const AvatarFrame({super.key, this.size = 220, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FramePainter(),
        child: Padding(
          padding: EdgeInsets.all(size * 0.09),
          child: ClipOval(child: _buildImage()),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (imageUrl != null) {
      final isRemote = imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://');
      return isRemote
          ? Image.network(imageUrl!, fit: BoxFit.cover, gaplessPlayback: true)
          : Image.file(File(imageUrl!), fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Container(
      color: const Color(0xFFDDD0BA),
      child: Center(
        child: Icon(Icons.person, size: size * 0.45, color: const Color(0xFFAA9A88)),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final frameW = size.width * 0.08;

    final ringPaint = Paint()
      ..color = AppColors.avatarFrameDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = frameW;
    canvas.drawCircle(center, outerR - frameW / 2, ringPaint);

    final tickPaint = Paint()
      ..color = AppColors.avatarFrameMid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final innerR = outerR - frameW;
    final tickOuterR = outerR - frameW * 0.12;
    const count = 48;

    for (int i = 0; i < count; i++) {
      final angle = (2 * pi * i / count) - pi / 2;
      final p1 = Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle));
      final p2 = Offset(center.dx + tickOuterR * cos(angle), center.dy + tickOuterR * sin(angle));
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}
