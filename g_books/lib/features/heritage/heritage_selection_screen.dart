import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../state/app_state.dart';

/// Placeholder — 古蹟選擇畫面尚未實作
class HeritageSelectionScreen extends StatelessWidget {
  const HeritageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ParchmentScaffold(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '歡迎，${state.currentUser?.name ?? ''}！',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2A1A0A),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '古蹟選擇（即將實作）',
              style: TextStyle(fontSize: 18, color: Color(0xFF6A5A4A)),
            ),
          ],
        ),
      ),
    );
  }
}
