import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import '../../state/app_state.dart';

/// 管理者後台首頁：選擇要編輯的古蹟 → 進入編輯器（slot / 原料對應 / 物品）。
class AdminHeritagePickerScreen extends StatelessWidget {
  const AdminHeritagePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AppState>().currentStaff;
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded,
                      color: Color(0xFFD4A843), size: 26),
                  const SizedBox(width: 10),
                  const Text(
                    '選擇要編輯的古蹟',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    staff?.displayName ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => context.read<AppState>().logout(),
                    icon: const Icon(Icons.logout_rounded,
                        size: 18, color: Colors.white70),
                    label: const Text('登出',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    childAspectRatio: 0.74,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: mockHeritages.length,
                  itemBuilder: (_, i) => _HeritageTile(
                    heritage: mockHeritages[i],
                    onTap: () =>
                        context.push('/admin/edit/${mockHeritages[i].id}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeritageTile extends StatelessWidget {
  final HeritageModel heritage;
  final VoidCallback onTap;
  const _HeritageTile({required this.heritage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (heritage.cardImagePath.isNotEmpty)
              Image.asset(heritage.cardImagePath, fit: BoxFit.cover)
            else
              const ColoredBox(color: Color(0xFF24272A)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heritage.name.isNotEmpty ? heritage.name : '（未命名）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 14, color: Color(0xFFD4A843)),
                      SizedBox(width: 4),
                      Text('編輯設定',
                          style: TextStyle(
                              color: Color(0xFFD4A843), fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
