import 'package:flutter/material.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../services/fight_service.dart';

/// 進入攻防戰的載入介面（TODO.md 需求 1）。
///
/// 暗化的 `fight.png` 背景 + 置中半透明黑底橫幅（大標「<古蹟>攻防戰」、小標說明），
/// 右下角載入轉圈 + 全體參戰組頭像橫排（重疊、左在上、最多 4 個，超過以 +X 表示）。
/// 純視覺；顯示 / 淡出由 [FightScreen] 控制。
class FightLoadingOverlay extends StatelessWidget {
  /// 暗底背景圖（`assets/heritages/<hid>/fight.png`）。
  final String fightImagePath;

  /// 大標題（通常為「<古蹟名>攻防戰」）。
  final String title;

  /// 參戰組（取其頭像橫排顯示）。
  final List<FightGroup> groups;

  const FightLoadingOverlay({
    super.key,
    required this.fightImagePath,
    required this.title,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF120D08),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 暗化的攻防戰背景。
          Image.asset(
            fightImagePath,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xCC0B0805)),
            ),
          ),
          // 置中半透明黑底橫幅。
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding:
                  const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33D4A843)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '透過答題攻打敵方的古蹟部件，來獲得第一名吧',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      letterSpacing: 2,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右下角：頭像橫排 + 轉圈。
          Positioned(
            right: 28,
            bottom: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AvatarStrip(groups: groups),
                const SizedBox(width: 16),
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(Color(0xFFD4A843)),
                    backgroundColor: Color(0x33FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 參戰組頭像橫排：重疊（左在上），最多顯示 4 個，超過以「+X」圓表示（置於最上層 = 最左）。
class _AvatarStrip extends StatelessWidget {
  final List<FightGroup> groups;
  const _AvatarStrip({required this.groups});

  static const double _size = 44;
  static const double _step = 30; // 重疊：每個往右位移 _step

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox(width: _size, height: _size);

    final shown = groups.length > 4 ? groups.sublist(0, 4) : groups;
    final overflow = groups.length - shown.length;

    // 由左到右排列的元素：超過時 +X 圓在最左（最上層）。
    final items = <Widget>[
      if (overflow > 0) _overflowChip(overflow),
      for (final g in shown) _avatar(g.avatarUrl),
    ];
    final width = _size + (items.length - 1) * _step;

    return SizedBox(
      width: width,
      height: _size,
      child: Stack(
        // 左在上：最左的元素最後畫（疊在最上）。
        children: [
          for (var i = items.length - 1; i >= 0; i--)
            Positioned(left: i * _step, child: items[i]),
        ],
      ),
    );
  }

  Widget _ring({required Widget child}) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE7CF9A), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 4),
          ],
        ),
        child: ClipOval(child: child),
      );

  Widget _avatar(String? url) => _ring(
        child: AvatarImage(
          url: url,
          width: _size,
          height: _size,
          placeholder: const ColoredBox(
            color: Color(0xFFDDD0BA),
            child: Icon(Icons.person, size: 22, color: Color(0xFFAA9A88)),
          ),
        ),
      );

  Widget _overflowChip(int n) => _ring(
        child: ColoredBox(
          color: const Color(0xCC000000),
          child: Center(
            child: Text(
              '+$n',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}
