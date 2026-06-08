import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../state/app_state.dart';

/// 教師登入後的占位頁。現階段教師無編輯權限（僅管理者可編輯古蹟設定）。
class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AppState>().currentStaff;
    return ParchmentScaffold(
      child: Stack(
        children: [
          Positioned(
            top: 24,
            right: 28,
            child: TextButton.icon(
              onPressed: () => context.read<AppState>().logout(),
              icon: const Icon(Icons.logout_rounded,
                  size: 18, color: AppColors.labelText),
              label: const Text('登出',
                  style: TextStyle(color: AppColors.labelText, fontSize: 15)),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_rounded,
                    size: 64, color: AppColors.labelText),
                const SizedBox(height: 20),
                Text(
                  '${staff?.displayName ?? '教師'}，您好',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.labelText,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '教師功能開發中，敬請期待。',
                  style: TextStyle(fontSize: 16, color: AppColors.labelText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
