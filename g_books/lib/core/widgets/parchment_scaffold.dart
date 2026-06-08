import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 共用底版。預設為純色羊皮紙底；給 [backgroundImage] 則改鋪滿背景圖。
class ParchmentScaffold extends StatelessWidget {
  final Widget child;
  final String? backgroundImage;

  const ParchmentScaffold({super.key, required this.child, this.backgroundImage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchmentBg,
      body: backgroundImage == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(backgroundImage!, fit: BoxFit.cover),
                child,
              ],
            ),
    );
  }
}
