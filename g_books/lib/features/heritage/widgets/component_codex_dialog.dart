import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/component_data.dart';
import '../../../data/models/component_model.dart';
import '../../../state/heritage_board_controller.dart';
import 'component_card.dart';
import 'component_detail_dialog.dart';

/// 原料庫圖鑑：列出該古蹟全部原料（依等級分組），顯示擁有數量（未擁有顯示 ×0），
/// 點任一原料可看詳細介紹。
class ComponentCodexDialog extends StatelessWidget {
  final String heritageId;
  const ComponentCodexDialog({super.key, required this.heritageId});

  @override
  Widget build(BuildContext context) {
    final board = context.watch<HeritageBoardController>();
    final all = componentsOf(heritageId);
    final byLevel = <int, List<ComponentModel>>{1: [], 2: [], 3: []};
    for (final c in all) {
      byLevel.putIfAbsent(c.level, () => []).add(c);
    }

    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: const Color(0xFF1F2225),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white24),
      ),
      // 幾乎佔滿整個畫面（四周各留 20）。
      child: SizedBox(
        width: screen.width - 40,
        height: screen.height - 40,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: Color(0xFFD4A843)),
                  const SizedBox(width: 10),
                  const Text(
                    '原料庫',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _statChip('總原料', board.totalCount, const Color(0xFFD4A843)),
                  const SizedBox(width: 8),
                  _statChip('已使用', board.usedCount, const Color(0xFF6FBF73)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final lv in const [1, 2, 3])
                        _levelSection(context, lv, byLevel[lv] ?? [], board),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(color: color, fontSize: 12, letterSpacing: 1)),
          const SizedBox(width: 6),
          Text('$value',
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _levelSection(
    BuildContext context,
    int level,
    List<ComponentModel> items,
    HeritageBoardController board,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    const labels = {1: '初級原料', 2: '中級原料', 3: '高級原料'};
    const colors = {
      1: Color(0xFF6FBF73),
      2: Color(0xFFE3B341),
      3: Color(0xFFD9534F),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Row(
            children: [
              Container(width: 4, height: 16, color: colors[level]),
              const SizedBox(width: 8),
              Text(
                labels[level] ?? '',
                style: TextStyle(
                  color: colors[level],
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 20,
          runSpacing: 18,
          children: items.map((c) {
            final qty = board.qty(c.id);
            return GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) =>
                    ComponentDetailDialog(component: c, quantity: qty),
              ),
              child: ComponentCard(
                component: c,
                size: 132,
                quantity: qty,
                showName: true,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
