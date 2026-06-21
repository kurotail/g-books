import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 進入古蹟頁前的載入畫面：登入頁同款背景 + 置中 logo + 右下角轉圈。
/// 純視覺元件，顯示/隱藏由呼叫端控制（例如資源預載完成後淡出）。
/// 註：右下角暫用系統轉圈，之後會換成自製 loading icon。
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  /// 圖片載入收尾：已在快取（同步載入）→ 立即顯示；否則解碼完成那刻平滑淡入，
  /// 避免「啟動預載未命中或被快取淘汰」時露出純色底再硬跳出圖。
  static Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.parchmentBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景圖（與其他頁一致；已於啟動時預載，未命中時平滑淡入不硬跳）。
          Image.asset(
            'assets/images/bg_login.png',
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: _fadeIn,
          ),
          // 四周暈影，讓中央更聚焦。
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [Color(0x00000000), Color(0x33000000)],
                  stops: [0.6, 1.0],
                ),
              ),
            ),
          ),
          // logo 置中（略偏上）。
          Align(
            alignment: const Alignment(0, -0.12),
            child: Image.asset(
              'assets/logo.png',
              width: 340,
              gaplessPlayback: true,
              frameBuilder: _fadeIn,
            ),
          ),
          // 右下角轉圈。
          const Positioned(
            right: 36,
            bottom: 36,
            child: SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                valueColor: AlwaysStoppedAnimation(Color(0xFF3A2A18)),
                backgroundColor: Color(0x33000000),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
