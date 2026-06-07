import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 進入古蹟頁前的載入畫面：羊皮紙底 + 置中 logo + 右下角轉圈。
/// 純視覺元件，顯示/隱藏由呼叫端控制（例如資源預載完成後淡出）。
/// 註：右下角暫用系統轉圈，之後會換成自製 loading icon。
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.parchmentBg,
      child: Stack(
        children: [
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
            child: Image.asset('assets/logo.png', width: 340),
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
