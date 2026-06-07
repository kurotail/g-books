import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ParchmentScaffold extends StatelessWidget {
  final Widget child;

  const ParchmentScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchmentBg,
      body: child,
    );
  }
}
