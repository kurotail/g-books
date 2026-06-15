import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import 'widgets/info_dialog.dart';

class HeritageSelectionScreen extends StatefulWidget {
  const HeritageSelectionScreen({super.key});

  @override
  State<HeritageSelectionScreen> createState() =>
      _HeritageSelectionScreenState();
}

class _HeritageSelectionScreenState extends State<HeritageSelectionScreen> {
  late final PageController _pageController;
  int _currentIndex = kInitialHeritageIndex;
  bool _isPanelVisible = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.28,
      initialPage: _currentIndex,
    );
    _pageController.addListener(_onPageScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final h in mockHeritages) {
        if (h.cardImagePath.isNotEmpty) {
          precacheImage(AssetImage(h.cardImagePath), context);
        }
      }
    });
  }

  void _onPageScroll() {
    final page = _pageController.page;
    if (page == null) return;
    final nearest = page.round();
    if (nearest != _currentIndex) {
      setState(() => _currentIndex = nearest);
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    super.dispose();
  }

  HeritageModel get _current => mockHeritages[_currentIndex];

  String get _bgPath {
    final path = _current.cardImagePath;
    if (path.isNotEmpty) return path;
    return mockHeritages
        .firstWhere((h) => h.cardImagePath.isNotEmpty)
        .cardImagePath;
  }

  void _togglePanel() => setState(() => _isPanelVisible = !_isPanelVisible);

  void _showInfo() {
    InfoDialog.showHeritage(
      context,
      heritageId: _current.id,
      title: _current.name,
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
        children: [
          // Background image — cross-fades on heritage change
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: Image.asset(
                _bgPath,
                key: ValueKey(_bgPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          // Dark overlay — lighter when panel collapsed so full image shows
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              color: Color.fromRGBO(0, 0, 0, _isPanelVisible ? 0.58 : 0.30),
            ),
          ),
          // UI content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTopSection()),
                _buildCardPanel(),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  // ── Top section: heritage name + 出征 button ──────────────────────────────

  Widget _buildTopSection() {
    final h = _current;
    final isAssigned = h.status == HeritageStatus.assigned;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // Heritage name + 古蹟資訊 button — fade out when panel collapsed
          IgnorePointer(
            ignoring: !_isPanelVisible,
            child: AnimatedOpacity(
              opacity: _isPanelVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      h.name.isNotEmpty ? h.name : '— — —',
                      key: ValueKey('name_${h.id}'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: h.name.isNotEmpty
                            ? const Color(0xFFD4A843)
                            : Colors.white24,
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        shadows: const [
                          Shadow(
                            color: Color(0xBB000000),
                            blurRadius: 12,
                            offset: Offset(2, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InfoButton(onTap: _showInfo),
                ],
              ),
            ),
          ),
          const Spacer(flex: 3),
          // 出征 button — fades out when panel collapsed
          IgnorePointer(
            ignoring: !_isPanelVisible,
            child: AnimatedOpacity(
              opacity: _isPanelVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _GoButton(
                status: h.status,
                onTap: isAssigned ? () => context.go('/my-heritage') : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Card panel (collapsible) ───────────────────────────────────────────────

  static const double _panelFullHeight = 300.0;
  static const double _handleHeight = 36.0;
  static const double _cardsHeight = _panelFullHeight - _handleHeight; // 264

  Widget _buildCardPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      height: _isPanelVisible ? _panelFullHeight : _handleHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      // OverflowBox decouples layout height from AnimatedContainer's clip
      // constraint, eliminating RenderFlex overflow during animation.
      child: OverflowBox(
        maxHeight: _panelFullHeight,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            // Drag-handle toggle
            GestureDetector(
              onTap: _togglePanel,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: _handleHeight,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Icon(
                        _isPanelVisible
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.white38,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Cards carousel
            SizedBox(
              height: _cardsHeight,
              child: PageView.builder(
                controller: _pageController,
                itemCount: mockHeritages.length,
                itemBuilder: (_, i) => AnimatedBuilder(
                  animation: _pageController,
                  builder: (_, child) {
                    double scale = i == _currentIndex ? 1.0 : 0.85;
                    if (_pageController.position.haveDimensions) {
                      final diff = (_pageController.page! - i).abs();
                      scale = (1.0 - diff * 0.15).clamp(0.85, 1.0);
                    }
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: _HeritageCard(heritage: mockHeritages[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info button (top-right) ────────────────────────────────────────────────────

class _InfoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Color.fromRGBO(0, 0, 0, 0.55),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD4A843)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline,
                color: Color(0xFFD4A843), size: 16),
            SizedBox(width: 6),
            Text(
              '古蹟資訊',
              style: TextStyle(
                color: Color(0xFFD4A843),
                fontSize: 13,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Go button ─────────────────────────────────────────────────────────────────

class _GoButton extends StatelessWidget {
  final HeritageStatus status;
  final VoidCallback? onTap;

  const _GoButton({required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final canGo = status == HeritageStatus.assigned;
    final label = switch (status) {
      HeritageStatus.assigned => '出 征',
      HeritageStatus.locked => '尚未開放',
      HeritageStatus.completed => '查看結果',
    };

    return GestureDetector(
      onTap: canGo ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
        decoration: BoxDecoration(
          color: canGo
              ? const Color(0xFF1E1E1E)
              : Color.fromRGBO(0, 0, 0, 0.3),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: canGo ? const Color(0xFFD4A843) : Colors.white24,
            width: 1.5,
          ),
          boxShadow: canGo
              ? [
                  const BoxShadow(
                    color: Color(0x4DD4A843),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⚔',
              style: TextStyle(
                fontSize: 18,
                color: canGo
                    ? const Color(0xFFD4A843)
                    : Colors.white24,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: canGo ? Colors.white : Colors.white38,
                fontSize: 18,
                letterSpacing: 5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Heritage card ──────────────────────────────────────────────────────────────

class _HeritageCard extends StatelessWidget {
  final HeritageModel heritage;

  const _HeritageCard({required this.heritage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            if (heritage.cardImagePath.isNotEmpty)
              Image.asset(heritage.cardImagePath, fit: BoxFit.cover)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A1A2A), Color(0xFF0A0A14)],
                  ),
                ),
              ),

            // Locked overlay
            if (heritage.status == HeritageStatus.locked) ...[
              ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.62)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      color: Color.fromRGBO(255, 255, 255, 0.35),
                      size: 44,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '未解鎖',
                      style: TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.35),
                        fontSize: 13,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Completed badge (reserved)
            if (heritage.status == HeritageStatus.completed)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '已完成',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

