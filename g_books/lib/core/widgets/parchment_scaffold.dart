import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 共用底版：滿版背景圖 + 內容層。
///
/// - [backgroundImage] 預設用登入頁同款背景（`bg_login.png`），各頁可覆蓋成自己的圖。
/// - 背景圖**不受鍵盤影響**：`resizeToAvoidBottomInset: false` 讓背景維持滿版不浮動，
///   僅內容層依鍵盤高度（`viewInsets.bottom`）上推避開鍵盤。
class ParchmentScaffold extends StatelessWidget {
  final Widget child;
  final String backgroundImage;

  const ParchmentScaffold({
    super.key,
    required this.child,
    this.backgroundImage = 'assets/images/bg_login.png',
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: AppColors.parchmentBg,
      // 背景圖固定滿版、不隨鍵盤縮放；內容自行避開鍵盤（見下方 Padding）。
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(backgroundImage, fit: BoxFit.cover),
          Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: child,
          ),
        ],
      ),
    );
  }
}
