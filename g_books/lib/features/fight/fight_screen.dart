import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets/avatar_image.dart';
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import '../../data/component_data.dart' show componentById, componentsOf;
import '../../data/slot_data.dart' show slotsOf;
import '../../state/app_state.dart';
import '../../services/fight_service.dart';
import '../../services/game_state_service.dart';
import 'widgets/fight_loading_overlay.dart';

/// 攻防戰（QUIZ2）主畫面：載入 → 古蹟世界地圖（拖曳縮放、各組島嶼即時戰況）→
/// 時間到結算排行榜。攻擊 / 補給修復等互動於後續階段接上（此檔先建好地圖底層與骨架）。
///
/// 後端對接點全部走 [FightService]（Mock 驅動可離線開發；切 [kUseBackend] 換 Api）。
class FightScreen extends StatefulWidget {
  const FightScreen({super.key});

  @override
  State<FightScreen> createState() => _FightScreenState();
}

class _FightScreenState extends State<FightScreen> with TickerProviderStateMixin {
  // ── 16 格分散填入順序：避免 1、2、3、4 連號相鄰，視覺上平均分散到全圖。 ───────────
  static const List<int> _cellOrder = [
    5, 10, 0, 15, 3, 12, 6, 9, 1, 14, 8, 7, 2, 13, 4, 11,
  ];

  // 島嶼網格在 viewport 內的配置區（避開上方倒數 / 標題與右上補給島）。
  static const double _gridLeft = 0.08;
  static const double _gridRight = 0.92;
  static const double _gridTop = 0.34;
  static const double _gridBottom = 0.88;

  final TransformationController _tc = TransformationController();

  bool _loading = true;
  bool _timeUp = false;
  // 曾進入過 quiz2，才把「階段離開 quiz2」視為時間到（避免非 quiz2 進場時誤觸結算）。
  bool _wasQuiz2 = false;
  List<LeaderboardEntry>? _leaderboard; // 非 null → 顯示排行榜覆蓋層
  bool _loadingBoard = false;

  List<FightGroup> _groups = const [];
  GameStateSnapshot? _state;
  StreamSubscription<FightEvent>? _eventSub;
  StreamSubscription<GameStateSnapshot>? _gameSub;
  Timer? _ticker;

  int _selfId = 0;
  late HeritageModel _heritage;

  // App 內「我方已損毀」通知（需求 4）：偵測自己組新損毀的格時跳出，數秒後自動消失。
  final List<_FightNotice> _notices = [];
  int _noticeSeq = 0;

  @override
  void initState() {
    super.initState();
    _heritage = mockHeritages.firstWhere(
      (h) => h.status == HeritageStatus.assigned,
      orElse: () => mockHeritages.first,
    );
    _selfId = context.read<AppState>().currentGroup?.id ?? 0;
    _load();
    // 每秒刷新倒數。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  String get _heritageId => _heritage.id;

  Future<void> _load() async {
    final fight = context.read<FightService>();
    final game = context.read<GameStateService>();

    // 倒數狀態：先取一次，並訂閱階段變化（時間到 / 老師結束 → 回 NORMAL 觸發結算）。
    try {
      _state = await game.fetch();
      if (_state?.phase == GamePhase.quiz2) _wasQuiz2 = true;
    } catch (_) {}
    _gameSub = game.watch().listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s.phase == GamePhase.quiz2) {
        _wasQuiz2 = true;
      } else if (_wasQuiz2 && !_timeUp) {
        _enterTimeUp(); // 曾在 quiz2，現在離開 → 時間到 / 老師結束。
      }
    });

    // 預載地圖與島嶼圖資。
    await _precache();

    // 取全體組別狀態。
    try {
      _groups = await fight.fetchAllGroups(
        selfUserId: _selfId,
        heritageId: _heritageId,
      );
    } catch (_) {
      _groups = const [];
    }
    if (!mounted) return;

    // 訂閱戰況事件：有人被打 / 修復 → refetch 全體狀態即時更新地圖。
    _eventSub = fight.watchEvents().listen(_onFightEvent);

    // 載入畫面至少停留一下，避免一閃而過。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _precache() async {
    if (!mounted) return;
    final paths = <String>[
      'assets/images/fight_map.png',
      'assets/images/supply_station.png',
      'assets/icons/buttons/my_heritages_btn.png',
      'assets/icons/buttons/supply_station_btn.png',
      'assets/icons/times_up.png',
      'assets/heritages/$_heritageId/fight.png',
      'assets/heritages/$_heritageId/main.png',
      'assets/heritages/$_heritageId/enemy.png',
      // 島嶼上要畫的元件圖。
      for (final c in componentsOf(_heritageId)) c.imagePath,
    ];
    final jobs = <Future<void>>[
      for (final p in paths) precacheImage(AssetImage(p), context, onError: (_, _) {}),
    ];
    await Future.wait(jobs);
  }

  void _onFightEvent(FightEvent e) async {
    // 收到 slot_update → 重新取全體狀態即時更新地圖。順帶比對自己組是否有新損毀的格，
    // 有就跳「我方已損毀 XX 物件」通知（需求 4；後端 slot_update 不含攻擊者，故不顯示哪組）。
    final fight = context.read<FightService>();
    final oldMine = _groupOf(_groups, _selfId);
    try {
      final groups = await fight.fetchAllGroups(
        selfUserId: _selfId,
        heritageId: _heritageId,
      );
      if (!mounted) return;
      final newMine = _groupOf(groups, _selfId);
      if (oldMine != null && newMine != null) {
        for (final s in newMine.slots.values) {
          if (!s.broken) continue;
          final was = oldMine.slots[s.slotId];
          if (was == null || !was.broken) {
            final name = componentById(_heritageId, s.type)?.name ?? '元件';
            _pushNotice('我方已損毀「$name」物件');
          }
        }
      }
      setState(() => _groups = groups);
    } catch (_) {}
  }

  FightGroup? _groupOf(List<FightGroup> groups, int userId) {
    for (final g in groups) {
      if (g.userId == userId) return g;
    }
    return null;
  }

  void _pushNotice(String text) {
    final id = _noticeSeq++;
    setState(() => _notices.add(_FightNotice(id, text)));
    Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _notices.removeWhere((n) => n.id == id));
    });
  }

  void _onTick() {
    if (!mounted) return;
    final st = _state;
    if (st != null && st.phase == GamePhase.quiz2) {
      if (st.remaining(DateTime.now()) == Duration.zero && !_timeUp) {
        _enterTimeUp();
        return;
      }
    }
    setState(() {}); // 刷新倒數文字
  }

  void _enterTimeUp() {
    setState(() => _timeUp = true);
  }

  Future<void> _openLeaderboard() async {
    setState(() => _loadingBoard = true);
    final fight = context.read<FightService>();
    List<LeaderboardEntry> board;
    try {
      board = await fight.fetchLeaderboard(
        selfUserId: _selfId,
        heritageId: _heritageId,
      );
    } catch (_) {
      board = const [];
    }
    if (!mounted) return;
    setState(() {
      _loadingBoard = false;
      _leaderboard = board;
    });
  }

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF23201B),
        title: const Text('結束遊戲', style: TextStyle(color: Colors.white)),
        content: const Text('確定要離開攻防戰並回到選擇古蹟頁面嗎？',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('結束', style: TextStyle(color: Color(0xFFD4A843))),
          ),
        ],
      ),
    );
    if (ok == true && mounted) context.go('/heritage-selection');
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _gameSub?.cancel();
    _ticker?.cancel();
    _tc.dispose();
    super.dispose();
  }

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A06),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildMap(),
          if (!_loading && !_timeUp) _buildHud(),
          if (!_loading && !_timeUp && _notices.isNotEmpty) _buildNotices(),
          if (_timeUp) _buildTimeUp(),
          if (_leaderboard != null) _buildLeaderboard(),
          // 載入畫面疊在最上，淡出移除。
          AnimatedOpacity(
            opacity: _loading ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: IgnorePointer(
              ignoring: !_loading,
              child: FightLoadingOverlay(
                fightImagePath: 'assets/heritages/$_heritageId/fight.png',
                title: '${_heritage.name}攻防戰',
                groups: _groups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 世界地圖（拖曳縮放） ────────────────────────────────────────────────────────
  Widget _buildMap() {
    final dragMargin = MediaQuery.sizeOf(context).shortestSide * 0.35;
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 1.0,
      maxScale: 6.0,
      boundaryMargin: EdgeInsets.all(dragMargin),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final scene = Rect.fromLTRB(
            -dragMargin,
            -dragMargin,
            viewport.width + dragMargin,
            viewport.height + dragMargin,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 地圖背景鋪滿整個可拖曳範圍。
              Positioned.fromRect(
                rect: scene,
                child: Image.asset(
                  'assets/images/fight_map.png',
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF15110B)),
                ),
              ),
              // 右上角補給站島嶼。
              ..._buildSupplyIsland(viewport),
              // 各組島嶼。
              ..._buildIslands(viewport),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildIslands(Size viewport) {
    final regionW = (_gridRight - _gridLeft) * viewport.width;
    final regionH = (_gridBottom - _gridTop) * viewport.height;
    final cellW = regionW / 4;
    final cellH = regionH / 4;
    final islandSize = (cellW < cellH ? cellW : cellH) * 0.92;

    final widgets = <Widget>[];
    for (var i = 0; i < _groups.length && i < _cellOrder.length; i++) {
      final cell = _cellOrder[i];
      final col = cell % 4;
      final row = cell ~/ 4;
      final cx = _gridLeft * viewport.width + (col + 0.5) * cellW;
      final cy = _gridTop * viewport.height + (row + 0.5) * cellH;
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: islandSize,
        height: islandSize,
      );
      final g = _groups[i];
      widgets.add(_buildIsland(g, rect, g.userId == _selfId));
    }
    return widgets;
  }

  Widget _buildIsland(FightGroup g, Rect rect, bool isSelf) {
    final img = isSelf
        ? 'assets/heritages/$_heritageId/main.png'
        : 'assets/heritages/$_heritageId/enemy.png';
    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => isSelf ? _onTapSelf() : _onTapEnemy(g),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(
                img,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            // 把各組已放置的元件都畫上去（損毀者變暗）。
            for (final s in g.slots.values)
              _buildSlotComponent(s, Size(rect.width, rect.height)),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotComponent(FightSlot s, Size islandSize) {
    final geo = slotsOf(_heritageId).where((x) => x.id == s.slotId);
    if (geo.isEmpty) return const SizedBox.shrink();
    final slot = geo.first;
    final comp = componentById(_heritageId, s.type);
    if (comp == null) return const SizedBox.shrink();
    final w = slot.w * islandSize.width;
    final h = slot.h * islandSize.height;
    final left = slot.cx * islandSize.width - w / 2;
    final top = slot.cy * islandSize.height - h / 2;
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Opacity(
        opacity: s.broken ? 0.35 : 1.0,
        child: Image.asset(
          comp.imagePath,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  List<Widget> _buildSupplyIsland(Size viewport) {
    final size = viewport.shortestSide * 0.18;
    final rect = Rect.fromCenter(
      center: Offset(viewport.width * 0.86, viewport.height * 0.18),
      width: size,
      height: size,
    );
    return [
      Positioned.fromRect(
        rect: rect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTapSupply,
          child: Image.asset(
            'assets/images/supply_station.png',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }

  // ── HUD（倒數 / 提示 / 左側選單 / 固定大小氣泡） ────────────────────────────────
  Widget _buildHud() {
    return Stack(
      children: [
        // 固定大小的氣泡（頭像 + 組名 + 血量），跟著島嶼移動但不隨縮放變大。
        _buildBubbleLayer(),
        // 上方倒數。
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(child: _countdownChip()),
        ),
        // 提示文字。
        const Positioned(
          top: 64,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '請選擇要查看的古蹟',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 2,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ),
        ),
        // 左上角選單：自己古蹟 / 文資補給站。
        Positioned(
          top: 14,
          left: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _menuBtn('assets/icons/buttons/my_heritages_btn.png', '自己古蹟',
                  _onTapSelf),
              const SizedBox(height: 10),
              _menuBtn('assets/icons/buttons/supply_station_btn.png', '文資補給站',
                  _onTapSupply),
            ],
          ),
        ),
      ],
    );
  }

  Widget _countdownChip() {
    final st = _state;
    final remaining =
        st != null ? st.remaining(DateTime.now()) : Duration.zero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x55D4A843)),
      ),
      child: Text(
        formatMmSs(remaining),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
    );
  }

  Widget _menuBtn(String asset, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xE0241E18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Image.asset(asset, fit: BoxFit.contain),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 固定大小氣泡層：每幀依 [_tc] 變換把島嶼中心投影到螢幕座標，氣泡本身不縮放
  /// （類似地圖地標），縮太小則淡出。
  Widget _buildBubbleLayer() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return AnimatedBuilder(
          animation: _tc,
          builder: (_, _) {
            final scale = _tc.value.getMaxScaleOnAxis();
            // 縮太小 → 氣泡淡出消失。
            final opacity = ((scale - 0.85) / 0.25).clamp(0.0, 1.0);
            final regionW = (_gridRight - _gridLeft) * viewport.width;
            final regionH = (_gridBottom - _gridTop) * viewport.height;
            final cellW = regionW / 4;
            final cellH = regionH / 4;
            final islandSize = (cellW < cellH ? cellW : cellH) * 0.92;

            final pins = <Widget>[];
            for (var i = 0; i < _groups.length && i < _cellOrder.length; i++) {
              final cell = _cellOrder[i];
              final col = cell % 4;
              final row = cell ~/ 4;
              final cx = _gridLeft * viewport.width + (col + 0.5) * cellW;
              final cy = _gridTop * viewport.height + (row + 0.5) * cellH;
              // 氣泡錨在島嶼左緣中點。
              final anchor = Offset(cx - islandSize / 2, cy);
              final screen = MatrixUtils.transformPoint(_tc.value, anchor);
              final g = _groups[i];
              pins.add(Positioned(
                // 氣泡寬約 132，置於錨點左側。
                left: screen.dx - 138,
                top: screen.dy - 26,
                child: Opacity(
                  opacity: opacity,
                  child: _GroupBubble(
                    group: g,
                    heritageId: _heritageId,
                    isSelf: g.userId == _selfId,
                  ),
                ),
              ));
            }
            return IgnorePointer(
              ignoring: opacity < 0.5,
              child: Stack(clipBehavior: Clip.none, children: pins),
            );
          },
        );
      },
    );
  }

  // ── App 內「我方已損毀」通知（需求 4） ─────────────────────────────────────────
  Widget _buildNotices() {
    return Positioned(
      top: 96,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final n in _notices) _noticeCard(n)],
        ),
      ),
    );
  }

  Widget _noticeCard(_FightNotice n) {
    // 由上滑入 + 淡入。
    return TweenAnimationBuilder<double>(
      key: ValueKey(n.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF03A1512),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE06A5A)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.heart_broken_rounded,
                color: Color(0xFFE06A5A), size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                n.text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 時間到 / 排行榜 ─────────────────────────────────────────────────────────────
  Widget _buildTimeUp() {
    return ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icons/times_up.png', width: 320,
                errorBuilder: (_, _, _) => const Text('時間到',
                    style: TextStyle(color: Colors.white, fontSize: 40))),
            const SizedBox(height: 24),
            _goldButton(
              label: '查看排行榜',
              loading: _loadingBoard,
              onTap: _loadingBoard ? null : _openLeaderboard,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboard() {
    final board = _leaderboard ?? const [];
    return ColoredBox(
      color: const Color(0xF2000000),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const Text('攻防戰結果',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4)),
              const SizedBox(height: 16),
              Expanded(
                child: board.isEmpty
                    ? const Center(
                        child: Text('暫無結果',
                            style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        itemCount: board.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _leaderRow(board[i]),
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _goldButton(label: '結束遊戲', onTap: _confirmEnd),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leaderRow(LeaderboardEntry e) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF231F19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: e.rank == 1 ? const Color(0xFFD4A843) : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${e.rank}',
                style: TextStyle(
                    color: e.rank == 1
                        ? const Color(0xFFD4A843)
                        : Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ),
          ClipOval(
            child: AvatarImage(
              url: e.avatarUrl,
              width: 40,
              height: 40,
              placeholder: const ColoredBox(
                color: Color(0xFFDDD0BA),
                child: Icon(Icons.person, size: 22, color: Color(0xFFAA9A88)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(e.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          Row(
            children: [
              Text(e.hpMax > 0 ? '${e.hp} / ${e.hpMax}' : '${e.hp}',
                  style: const TextStyle(
                      color: Color(0xFFE7CF9A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Text('血量',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goldButton({
    required String label,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD4A843),
          borderRadius: BorderRadius.circular(24),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF2A1A0A))),
              )
            : Text(label,
                style: const TextStyle(
                    color: Color(0xFF2A1A0A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
      ),
    );
  }

  // ── 互動（攻擊 / 補給 / 自己島）：後續階段接上實作 ───────────────────────────────
  void _onTapEnemy(FightGroup g) {
    // TODO(攻擊流程)：放大該島 → 提示可攻擊部位 → 確認 → target 取題作答 → 成功/失敗介面。
    _todoToast('攻打「${g.displayName}」的流程於下一階段實作');
  }

  void _onTapSelf() {
    // TODO(自己島)：放大自己島，列出剩餘 / 損毀元件清單。
    _todoToast('查看自己古蹟（剩餘 / 損毀元件）於下一階段實作');
  }

  void _onTapSupply() {
    // TODO(補給站)：縮小攻防島、放大補給站，列出已損元件 → 依難度取修復題。
    _todoToast('文資補給站修復流程於下一階段實作');
  }

  void _todoToast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2A2420),
      ));
  }
}

/// 一則「我方已損毀」通知（id 供逾時移除比對）。
class _FightNotice {
  final int id;
  final String text;
  const _FightNotice(this.id, this.text);
}

/// 固定大小氣泡：頭像 + 組名 + 血量條（剩餘 / 上限）。敵我以邊框色區分。
class _GroupBubble extends StatelessWidget {
  final FightGroup group;
  final String heritageId;
  final bool isSelf;
  const _GroupBubble({
    required this.group,
    required this.heritageId,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final hp = group.hp(heritageId);
    final hpMax = group.hpMax(heritageId);
    final ratio = hpMax == 0 ? 0.0 : (hp / hpMax).clamp(0.0, 1.0);
    final accent = isSelf ? const Color(0xFF6FC36F) : const Color(0xFFE06A5A);
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE61A1610),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
      ),
      child: Row(
        children: [
          ClipOval(
            child: AvatarImage(
              url: group.avatarUrl,
              width: 30,
              height: 30,
              placeholder: const ColoredBox(
                color: Color(0xFFDDD0BA),
                child: Icon(Icons.person, size: 16, color: Color(0xFFAA9A88)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                // 血量條。
                Stack(
                  children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$hp / $hpMax',
                    style: const TextStyle(
                        color: Color(0xFFE7CF9A),
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
