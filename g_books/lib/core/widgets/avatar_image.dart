import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/api_client.dart' show resolveMediaUrl;

/// 頭像圖片來源解析：把後端相對路徑補成絕對網址（[resolveMediaUrl]），依 http(s)
/// 與否選用 [Image.network] / [Image.file]，載入失敗或無 url 時退回 [placeholder]。
///
/// 只負責「url → 圖」，外層的圓框 / 裁切 / 尺寸由呼叫端決定（各處外觀不同）。
class AvatarImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 無 url 或載入失敗時顯示的後備（預設人像）。
  final Widget placeholder;

  const AvatarImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final u = resolveMediaUrl(url);
    if (u == null || u.isEmpty) return placeholder;
    final remote = u.startsWith('http://') || u.startsWith('https://');
    return remote
        ? Image.network(u,
            width: width, height: height, fit: fit, gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder)
        : Image.file(File(u),
            width: width, height: height, fit: fit, gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder);
  }
}
