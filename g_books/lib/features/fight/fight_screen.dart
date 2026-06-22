// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets/avatar_frame.dart';
import '../../core/widgets/avatar_image.dart';
import '../../data/heritage_data.dart';
import '../../data/models/component_model.dart';
import '../../data/models/heritage_model.dart';
import '../../data/component_data.dart' show componentById, componentsOf;
import '../../data/map_cell_data.dart' show mapCellsOf;
import '../../data/slot_data.dart' show slotsOf;
import '../../state/app_state.dart';
import '../../services/api_client.dart' show ApiException;
import '../../services/fight_service.dart';
import '../../services/game_state_service.dart';
import '../../services/quiz_service.dart';
import 'fight_map_geometry.dart';
import 'widgets/fight_loading_overlay.dart';
import 'widgets/fight_quiz_sheet.dart';

/// 攻防戰（QUIZ2）主畫面：載入 → 古蹟世界地圖（拖曳縮放、各組島嶼即時戰況）→
/// 時間到結算排行榜。攻擊 / 補給修復等互動於後續階段接上（此檔先建好地圖底層與骨架）。
///
/// 後端對接點全部走 [FightService]（Mock 驅動可離線開發；切 [kUseBackend] 換 Api）。
class FightScreen extends StatefulWidget {
  final FightInitialData? initialData;

  const FightScreen({super.key, this.initialData});

  @override
  State<FightScreen> createState() => _FightScreenState();
}

class FightInitialData {
  final GameStateSnapshot? state;
  final List<FightGroup> groups;

  const FightInitialData({required this.state, required this.groups});
}

class _FightScreenState extends State<FightScreen>
    with TickerProviderStateMixin {
  // 後備島格分散填入順序：管理者尚未在「世界地圖」設定島格時，用此順序在主島內排出
  // 一個分散的 4×4 後備格（避免 1、2、3、4 連號相鄰）。
  static const List<int> _fallbackOrder = [
    5,
    10,
    0,
    15,
    3,
    12,
    6,
    9,
    1,
    14,
    8,
    7,
    2,
    13,
    4,
    11,
  ];

  static const double _maxScale = 6.0;

  final TransformationController _tc = TransformationController();
  // 鏡頭聚焦動畫（點島放大 / 還原），與檢視古蹟拆卸聚焦同一套作法。
  late final AnimationController _viewAnim;
  Matrix4Tween? _viewTween;
  Matrix4 _savedTransform = Matrix4.identity(); // 聚焦前的鏡頭，供還原
  bool _cameraInit = false; // 首次進場是否已套用「顯示整個世界」鏡頭
  Size _viewport = Size.zero;

  // 左上角可展開面板（頭像 → 我的古蹟 / 文資補給）。
  late final AnimationController _panelCtrl;
  late final Animation<double> _panelCurve;
  bool _panelOpen = false;

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

  // 被攻打小彈窗（需求 8）：偵測自己組新損毀的格時即時跳出小卡片（附該元件破損圖，需求 3），
  // 數秒後自動消失。取代舊的下方橫幅通知（需求 7）。
  final List<_AttackPop> _attackPops = [];
  int _popSeq = 0;
  // 聚焦自己島嶼時，左上角「查看詳細狀況」可展開面板是否展開（剩餘 / 損毀物件）。
  bool _selfStatusExpanded = false;

  // ── 互動覆蓋層狀態 ───────────────────────────────────────────────────────────
  // 可攻擊部位的閃爍提示。
  late final AnimationController _blink;
  // 鏡頭聚焦中的島嶼（點島放大後原地互動）；null = 在世界全景。
  FightGroup? _focused;
  // 聚焦中的島嶼是否為自己（自己島不可攻擊，左上改顯示戰況面板）。
  bool get _selfFocused => _focused != null && _focused!.userId == _selfId;
  // 文資補給站（修復）面板開啟中。
  bool _supplyOpen = false;
  bool _supplyFocused = false;
  // 正在開 target session（取題中）顯示轉圈。
  bool _opening = false;
  // 作答中的題目與其目標脈絡。
  QuizQuestion? _answerQ;
  _TargetCtx? _answerCtx;
  // 攻擊 / 修復結果畫面。
  _Outcome? _outcome;
  _AttackTarget? _attackTarget;
  Matrix4 _attackReturnTransform = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _heritage = mockHeritages.firstWhere(
      (h) => h.status == HeritageStatus.assigned,
      orElse: () => mockHeritages.first,
    );
    _selfId = context.read<AppState>().currentGroup?.id ?? 0;
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _viewAnim =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 380),
        )..addListener(() {
          final tw = _viewTween;
          if (tw != null) {
            _tc.value = tw.transform(
              Curves.easeInOut.transform(_viewAnim.value),
            );
          }
        });
    _panelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _panelCurve = CurvedAnimation(
      parent: _panelCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final initial = widget.initialData;
    if (initial != null) {
      _state = initial.state;
      if (_state?.phase == GamePhase.quiz2) _wasQuiz2 = true;
      _groups = initial.groups;
      _attachGameWatcher(context.read<GameStateService>());
      _eventSub = context.read<FightService>().watchEvents().listen(
        _onFightEvent,
      );
      unawaited(_finishIntroAfterDelay());
    } else {
      _load();
    }
    // 每秒刷新倒數。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  FightGroup? get _myGroup => _groupOf(_groups, _selfId);

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

    // 攻防戰載入畫面停留久一點（讓全組頭像 / 戰前氛圍看得清楚）。
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _precache() async {
    if (!mounted) return;
    final paths = <String>[
      'assets/images/bg_fight.png',
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
      for (final p in paths)
        precacheImage(AssetImage(p), context, onError: (_, _) {}),
    ];
    await Future.wait(jobs);
  }

  void _attachGameWatcher(GameStateService game) {
    _gameSub?.cancel();
    _gameSub = game.watch().listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s.phase == GamePhase.quiz2) {
        _wasQuiz2 = true;
      } else if (_wasQuiz2 && !_timeUp) {
        _enterTimeUp();
      }
    });
  }

  Future<void> _finishIntroAfterDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    setState(() => _loading = false);
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
            final comp = componentById(_heritageId, s.type);
            _pushAttackPop(comp?.name ?? '元件', comp?.brokenImagePath ?? '');
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

  void _pushAttackPop(String name, String brokenImagePath) {
    final id = _popSeq++;
    setState(() => _attackPops.add(_AttackPop(id, name, brokenImagePath)));
    Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _attackPops.removeWhere((n) => n.id == id));
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
    // 時間到即收掉所有進行中的互動（攻擊 / 修復選擇與取題），由結算畫面接手。
    setState(() {
      _timeUp = true;
      _focused = null;
      _supplyOpen = false;
      _supplyFocused = false;
      _selfStatusExpanded = false;
      _opening = false;
      _attackTarget = null;
    });
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
        content: const Text(
          '確定要離開攻防戰並回到選擇古蹟頁面嗎？',
          style: TextStyle(color: Colors.white70),
        ),
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
    _blink.dispose();
    _viewAnim.dispose();
    _panelCtrl.dispose();
    _tc.dispose();
    super.dispose();
  }

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2225),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 固定全螢幕天空底圖：畫在 InteractiveViewer 之外，不隨地圖縮放／平移，
          // 縮小看整個世界時也不會露出純色底。
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_fight.png',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF1F2225)),
            ),
          ),
          _buildMap(),
          if (!_loading && !_timeUp) _buildHud(),
          if (!_loading && !_timeUp && _attackPops.isNotEmpty) _buildAttackPops(),
          if (_attackTarget != null && !_timeUp) _buildAttackConfirm(),
          // 補給站 / 作答 / 結果（依序疊上；時間到則全部讓位給結算）。
          if (_supplyOpen && !_timeUp) _buildSupplyPanel(),
          if (_answerQ != null && !_timeUp) _buildAnswerSheet(),
          if (_outcome != null && !_timeUp) _buildOutcome(_outcome!),
          if (_opening && !_timeUp) _buildOpening(),
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

  // ── 世界地圖（主島 + 補給島；拖曳縮放，可縮到看見整個世界，點島放大聚焦） ────────────
  Widget _buildMap() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final vp = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = vp;
        final main = FightMapGeometry.mainRect(vp);
        // 首次進場：把鏡頭設成「顯示整個世界」（主島 + 補給島全貌）。
        if (!_cameraInit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _tc.value = _fitWorld(vp);
            setState(() => _cameraInit = true);
          });
        }
        // 允許縮小到比「整個世界」再小一些。
        final minScale = (_worldFitScale(vp) * 0.7).clamp(0.2, 1.0);
        final locked = _focused != null || _supplyFocused;
        return InteractiveViewer(
          transformationController: _tc,
          panEnabled: !locked,
          scaleEnabled: !locked,
          minScale: minScale,
          maxScale: _maxScale,
          boundaryMargin: EdgeInsets.all(vp.longestSide),
          child: SizedBox(
            width: vp.width,
            height: vp.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 主島（fight_map.png，依原圖長寬比鋪在 main 矩形）。
                Positioned.fromRect(
                  rect: main,
                  child: Image.asset(
                    'assets/images/fight_map.png',
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                // 補給島（浮在主島右上方）。
                _buildSupplyIsland(main),
                // 各組島嶼（落在世界地圖島格）。
                ..._buildIslands(main),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 各組島嶼落點：依設定（[mapCellsOf]）的島格；未設定時用後備分散格。group i → 第 i 格。
  List<({FightGroup g, Rect cell})> _placements(Rect main) {
    final rects = _cellRects(main);
    final out = <({FightGroup g, Rect cell})>[];
    for (var i = 0; i < _groups.length && i < rects.length; i++) {
      out.add((g: _groups[i], cell: rects[i]));
    }
    return out;
  }

  List<Rect> _cellRects(Rect main) {
    final cfg = mapCellsOf(_heritageId);
    if (cfg.isNotEmpty) {
      return [for (final c in cfg) FightMapGeometry.cellRect(c, main)];
    }
    return _fallbackCellRects(main);
  }

  /// 後備島格：管理者尚未設定時，在主島中央排出分散的 4×4 格。
  List<Rect> _fallbackCellRects(Rect main) {
    const left = 0.16, right = 0.84, top = 0.16, bottom = 0.84;
    final stepX = (right - left) / 4;
    final stepY = (bottom - top) / 4;
    final size = math.min(stepX * main.width, stepY * main.height) * 0.94;
    final out = <Rect>[];
    for (final cell in _fallbackOrder) {
      final col = cell % 4;
      final row = cell ~/ 4;
      final cx = main.left + (left + (col + 0.5) * stepX) * main.width;
      final cy = main.top + (top + (row + 0.5) * stepY) * main.height;
      out.add(
        Rect.fromCenter(center: Offset(cx, cy), width: size, height: size),
      );
    }
    return out;
  }

  List<Widget> _buildIslands(Rect main) {
    return [
      for (final p in _placements(main))
        _buildIsland(p.g, p.cell, p.g.userId == _selfId),
    ];
  }

  Widget _buildIsland(FightGroup g, Rect cell, bool isSelf) {
    final img = isSelf
        ? 'assets/heritages/$_heritageId/main.png'
        : 'assets/heritages/$_heritageId/enemy.png';
    // 島嶼圖（main/enemy.png 為正方形）置中於島格內，元件依此正方形對齊。
    final island = FightMapGeometry.islandSquare(cell);
    final local = Rect.fromLTWH(
      island.left - cell.left,
      island.top - cell.top,
      island.width,
      island.height,
    );
    final focusedHere = _focused?.userId == g.userId;
    // 聚焦敵島時，把「可攻擊 / 已選取」的格排到最後畫，確保其高亮蓋在相鄰元件之上、
    // 且能優先被點到（需求 4）。
    final slots = g.slots.values.toList();
    if (focusedHere && !isSelf) {
      int rank(FightSlot s) {
        if (_attackTarget?.target.userId == g.userId &&
            _attackTarget?.slot.slotId == s.slotId) {
          return 2;
        }
        return (!s.broken && !s.attackBlocked) ? 1 : 0;
      }

      slots.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    return Positioned.fromRect(
      rect: cell,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 點島 → 鏡頭聚焦（自己島：左上顯示戰況面板；敵島：原地攻擊）。
        onTap: () => _focusGroup(g),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: local,
              child: Image.asset(
                img,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            // 把各組已放置的元件都畫上去（損毀者用替身圖）；聚焦敵島時可攻擊格可點＋閃爍。
            for (final s in slots)
              _slotTile(
                g,
                s,
                local,
                sceneOffset: cell.topLeft,
                isSelf: isSelf,
                focused: focusedHere,
              ),
          ],
        ),
      ),
    );
  }

  /// 島上一個元件磚。非聚焦 / 自己島：純展示。聚焦敵島：可攻擊→閃爍可點發動攻擊；
  /// 損毀 / 待對方修復→點了出提示。
  Widget _slotTile(
    FightGroup g,
    FightSlot s,
    Rect island, {
    required Offset sceneOffset,
    required bool isSelf,
    required bool focused,
  }) {
    final geo = slotsOf(_heritageId).where((x) => x.id == s.slotId);
    if (geo.isEmpty) return const SizedBox.shrink();
    final slot = geo.first;
    final comp = componentById(_heritageId, s.type);
    if (comp == null) return const SizedBox.shrink();
    final w = slot.w * island.width;
    final h = slot.h * island.height;
    final left = island.left + slot.cx * island.width - w / 2;
    final top = island.top + slot.cy * island.height - h / 2;
    final attackable = focused && !isSelf && !s.broken && !s.attackBlocked;
    final sceneRect = Rect.fromLTWH(
      sceneOffset.dx + left,
      sceneOffset.dy + top,
      w,
      h,
    );
    final selected =
        _attackTarget?.target.userId == g.userId &&
        _attackTarget?.slot.slotId == s.slotId;

    final image = Image.asset(
      // 損毀 → 改畫損毀替身圖（負 id）。
      s.broken ? comp.brokenImagePath : comp.imagePath,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    Widget tile = image;
    if (attackable || selected) {
      // 高亮光暈畫在元件「背後」（不遮住元件），且為填滿的放射狀光（中心不留洞）；
      // 元件本身跟著閃爍（透明度變化）（需求 3）。
      final accent = selected
          ? const Color(0xFFFF5B3D)
          : const Color(0xFFE0B84A);
      tile = AnimatedBuilder(
        animation: _blink,
        builder: (_, _) {
          final t = _blink.value;
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // 背後填滿光暈：中心較亮、向外漸隱，外圈再加柔光。
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.55 * (0.45 + 0.55 * t)),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3 + 0.45 * t),
                      blurRadius: 10 + 14 * t,
                      spreadRadius: 2 + 4 * t,
                    ),
                  ],
                ),
              ),
              // 元件本身：透明度隨閃爍變化。
              Opacity(opacity: 0.55 + 0.45 * t, child: image),
            ],
          );
        },
      );
    }

    if (!focused || isSelf) {
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: IgnorePointer(child: tile),
      );
    }
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (attackable) {
            _beginAttack(g, s, comp, sceneRect);
          } else if (s.broken) {
            _toast('「${comp.name}」已被攻破');
          } else {
            _toast('這格你已答錯過，需等對方修復後才能再攻擊');
          }
        },
        child: tile,
      ),
    );
  }

  Widget _buildSupplyIsland(Rect main) {
    return Positioned.fromRect(
      rect: FightMapGeometry.supplyRect(main),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 點補給島＝點選單「文資補給」按鈕（需求 6）：未聚焦先聚焦、已聚焦則開修復面板。
        onTap: _onTapSupply,
        child: Image.asset(
          'assets/images/supply_station.png',
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  // ── 鏡頭：顯示整個世界 / 聚焦某島 / 還原 ──────────────────────────────────────────
  Rect _worldRect(Size vp) {
    final main = FightMapGeometry.mainRect(vp);
    final r = main.expandToInclude(FightMapGeometry.supplyRect(main));
    return r.inflate(r.shortestSide * 0.06);
  }

  double _worldFitScale(Size vp) {
    final w = _worldRect(vp);
    return math.min(vp.width / w.width, vp.height / w.height);
  }

  Matrix4 _fitWorld(Size vp) {
    final w = _worldRect(vp);
    final s = _worldFitScale(vp);
    final off = Offset(vp.width / 2, vp.height / 2) - w.center * s;
    return Matrix4.identity()
      ..translateByDouble(off.dx, off.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// 把 [sceneRect]（島嶼正方形）放大置中，約占畫面寬 78%。
  Matrix4 _focusMatrix(Rect sceneRect) {
    final vp = _viewport;
    final s = ((vp.width * 0.78) / sceneRect.width).clamp(1.0, _maxScale);
    final off = Offset(vp.width / 2, vp.height / 2) - sceneRect.center * s;
    return Matrix4.identity()
      ..translateByDouble(off.dx, off.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Matrix4 _focusSupplyMatrix(Rect sceneRect) {
    final vp = _viewport;
    final s = ((vp.width * 0.34) / sceneRect.width).clamp(1.0, _maxScale);
    final off = Offset(vp.width / 2, vp.height / 2) - sceneRect.center * s;
    return Matrix4.identity()
      ..translateByDouble(off.dx, off.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Matrix4 _focusComponentMatrix(Rect sceneRect) {
    final vp = _viewport;
    final s = ((vp.width * 0.24) / sceneRect.width).clamp(2.0, _maxScale);
    final off = Offset(vp.width * 0.56, vp.height * 0.5) - sceneRect.center * s;
    return Matrix4.identity()
      ..translateByDouble(off.dx, off.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Offset _toScreen(Offset scene, Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    return Offset(t.x + s * scene.dx, t.y + s * scene.dy);
  }

  Rect _screenRect(Rect sceneRect, Matrix4 m) => Rect.fromPoints(
    _toScreen(sceneRect.topLeft, m),
    _toScreen(sceneRect.bottomRight, m),
  );

  void _animateTo(Matrix4 target) {
    _viewTween = Matrix4Tween(begin: _tc.value.clone(), end: target);
    _viewAnim.forward(from: 0);
  }

  Rect? _cellRectFor(FightGroup g, Rect main) {
    for (final p in _placements(main)) {
      if (p.g.userId == g.userId) return p.cell;
    }
    return null;
  }

  void _focusGroup(FightGroup g) {
    if (_timeUp) return;
    if (_focused?.userId == g.userId) return;
    final cell = _cellRectFor(g, FightMapGeometry.mainRect(_viewport));
    if (cell == null) return;
    if (_focused == null && !_supplyFocused) _savedTransform = _tc.value.clone();
    setState(() {
      _focused = g;
      // 聚焦自己島時，左上戰況面板預設收合。
      _selfStatusExpanded = false;
      _supplyFocused = false;
      _supplyOpen = false;
      _panelOpen = false;
      _attackTarget = null;
    });
    _panelCtrl.reverse();
    _animateTo(_focusMatrix(FightMapGeometry.islandSquare(cell)));
  }

  void _unfocus() {
    if (_focused == null && !_supplyFocused) return;
    setState(() {
      _focused = null;
      _supplyFocused = false;
      _attackTarget = null;
    });
    _animateTo(_savedTransform);
  }

  void _focusSupply() {
    if (_timeUp || _supplyFocused) return;
    final supply = FightMapGeometry.supplyRect(
      FightMapGeometry.mainRect(_viewport),
    );
    if (_focused == null && !_supplyFocused)
      _savedTransform = _tc.value.clone();
    setState(() {
      _focused = null;
      _supplyFocused = true;
      _supplyOpen = false;
      _panelOpen = false;
      _attackTarget = null;
    });
    _panelCtrl.reverse();
    _animateTo(_focusSupplyMatrix(supply));
  }

  // ── HUD（倒數 / 提示 / 左側面板 / 固定大小氣泡 / 聚焦列） ───────────────────────────
  Widget _buildHud() {
    final focused = _focused;
    final worldView = focused == null && !_supplyFocused;
    return Stack(
      children: [
        // 全景：固定大小的氣泡（頭像 + 組名 + 血量），跟著島嶼移動但不隨縮放變大。
        if (worldView) _buildBubbleLayer(),
        // 上方倒數。
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(child: _countdownChip()),
        ),
        if (worldView) ...[
          // 提示文字。
          const Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '請選擇你要攻打的古蹟',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  letterSpacing: 2,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ),
          ),
          // 左上角可展開面板（頭像 → 我的古蹟 / 文資補給）。
          Positioned(top: 14, left: 14, child: _buildPanel()),
        ] else if (_supplyFocused) ...[
          // 補給島內的「開始補給」按鈕（需求 1）＋ 右上角返回（需求 2）。
          _buildSupplyStartButton(),
          _buildBackTopRight(),
        ] else if (_selfFocused) ...[
          // 聚焦自己島：左上「查看詳細狀況」可展開面板（需求 5）＋ 右上角返回。
          Positioned(top: 12, left: 12, child: _buildSelfStatusPanel()),
          _buildBackTopRight(),
        ] else ...[
          // 聚焦敵島：左上標題＋右上角返回（需求 2）。
          Positioned(
            top: 12,
            left: 12,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(220.0, _viewport.width * 0.5),
              ),
              child: _focusTitleChip(focused!),
            ),
          ),
          _buildBackTopRight(),
        ],
      ],
    );
  }

  /// 右上角返回鈕（需求 2）：聚焦敵島 / 補給島時縮回世界全景。
  Widget _buildBackTopRight() {
    return Positioned(top: 12, right: 12, child: _backButton(_unfocus));
  }

  /// 補給島內「開始補給」按鈕（需求 1）：每幀依鏡頭把補給島投影到螢幕，置於島上開啟修復面板。
  Widget _buildSupplyStartButton() {
    return AnimatedBuilder(
      animation: _tc,
      builder: (_, _) {
        final main = FightMapGeometry.mainRect(_viewport);
        final supply = FightMapGeometry.supplyRect(main);
        final rect = _screenRect(supply, _tc.value);
        const btnW = 156.0;
        double left = rect.center.dx - btnW / 2;
        left = left.clamp(8.0, math.max(8.0, _viewport.width - btnW - 8));
        double top = rect.center.dy + rect.height * 0.14;
        top = top.clamp(8.0, math.max(8.0, _viewport.height - 60));
        return Positioned(
          left: left,
          top: top,
          width: btnW,
          child: Center(
            child: _goldButton(label: '開始補給', onTap: _openSupplyPanel),
          ),
        );
      },
    );
  }

  Widget _backButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xCC1F2225),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              '\u8fd4\u56de',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// 聚焦敵島時左上角的標題卡：古蹟名稱 + 可攻擊提示。
  Widget _focusTitleChip(FightGroup focused) {
    final g = _groupOf(_groups, focused.userId) ?? focused;
    const accent = Color(0xFFE06A5A);
    final attackable = g.slots.values
        .where((s) => !s.broken && !s.attackBlocked)
        .length;
    final hint = attackable > 0
        ? '點擊閃爍部件發動攻擊（可攻擊 $attackable 件）'
        : '目前沒有可攻擊的部件';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC1F2225),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '攻打 ${g.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _countdownChip() {
    final st = _state;
    final remaining = st != null ? st.remaining(DateTime.now()) : Duration.zero;
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

  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) {
      _panelCtrl.forward();
    } else {
      _panelCtrl.reverse();
    }
  }

  /// 左上角可展開面板（作法同檢視古蹟）：常駐頭像 + 組名，展開後只有「我的古蹟」與
  /// 「文資補給」兩項。
  Widget _buildPanel() {
    final group = context.read<AppState>().currentGroup;
    final name = group?.name ?? '';
    final username = group?.username ?? '';
    final avatar = group?.avatarUrl;
    return AnimatedBuilder(
      animation: _panelCurve,
      builder: (_, _) =>
          _panelSurface(_panelCurve.value, name, username, avatar),
    );
  }

  Widget _panelSurface(double t, String name, String username, String? avatar) {
    final tc = t.clamp(0.0, 1.0);
    return Container(
      width: 210,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xEB1F2225),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _togglePanel,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                AvatarFrame(size: 48, imageUrl: avatar),
                const SizedBox(width: 10),
                Expanded(child: _panelHeaderText(name, username)),
                Transform.rotate(
                  angle: tc * math.pi,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: tc,
              child: Opacity(opacity: tc, child: _panelMenu()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelHeaderText(String name, String username) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? '未命名小組' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        if (username.isNotEmpty)
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
      ],
    );
  }

  Widget _panelMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 6),
        _panelMenuBtn(
          'assets/icons/buttons/my_heritages_btn.png',
          '我的古蹟',
          _onTapSelf,
        ),
        _panelMenuBtn(
          'assets/icons/buttons/supply_station_btn.png',
          '文資補給',
          _onTapSupply,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(color: Colors.white12, height: 1),
        ),
        _panelMenuBtn(
          null,
          '小組資訊',
          _openGroupOverview,
          icon: Icons.groups_rounded,
        ),
        _panelMenuBtn(null, '登出', _logout, icon: Icons.logout_rounded),
      ],
    );
  }

  Widget _panelMenuBtn(
    String? asset,
    String label,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: asset == null
                  ? Icon(icon, color: const Color(0xFFD4A843), size: 30)
                  : Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 固定大小氣泡層：每幀依 [_tc] 變換把島嶼上緣投影到螢幕座標，氣泡本身不隨縮放變大
  /// （類似地圖地標），置於島嶼正上方。聚焦某島時整層不顯示（由 [_buildHud] 控制）。
  Widget _buildBubbleLayer() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final vp = Size(constraints.maxWidth, constraints.maxHeight);
        final main = FightMapGeometry.mainRect(vp);
        final placements = _placements(main);
        return AnimatedBuilder(
          animation: _tc,
          builder: (_, _) {
            final pins = <Widget>[];
            for (final p in placements) {
              final island = FightMapGeometry.islandSquare(p.cell);
              final screen = MatrixUtils.transformPoint(
                _tc.value,
                island.topCenter,
              );
              pins.add(
                Positioned(
                  // 氣泡寬約 132，置中於島嶼正上方。
                  left: screen.dx - 66,
                  top: screen.dy - 58,
                  child: _GroupBubble(
                    group: p.g,
                    heritageId: _heritageId,
                    isSelf: p.g.userId == _selfId,
                  ),
                ),
              );
            }
            return IgnorePointer(
              child: Stack(clipBehavior: Clip.none, children: pins),
            );
          },
        );
      },
    );
  }

  // ── 被攻打小彈窗（需求 8；附該元件破損圖，需求 3） ─────────────────────────────────
  Widget _buildAttackPops() {
    return Positioned(
      top: 70,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final p in _attackPops) _attackPopCard(p)],
        ),
      ),
    );
  }

  Widget _attackPopCard(_AttackPop p) {
    // 彈跳放大 + 淡入的小卡片。
    return TweenAnimationBuilder<double>(
      key: ValueKey(p.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (_, t, child) {
        final tc = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: tc,
          child: Transform.scale(scale: 0.85 + 0.15 * tc, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
        decoration: BoxDecoration(
          color: const Color(0xF22A1512),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE06A5A), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 該元件的破損圖（需求 3）。
            SizedBox(
              width: 40,
              height: 40,
              child: p.brokenImagePath.isEmpty
                  ? const Icon(
                      Icons.heart_broken_rounded,
                      color: Color(0xFFE06A5A),
                    )
                  : Image.asset(
                      p.brokenImagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.heart_broken_rounded,
                        color: Color(0xFFE06A5A),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '「${p.name}」被攻打了！',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '快到文資補給站修復！',
                  style: TextStyle(color: Color(0xFFFFC7B8), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 我方古蹟戰況（需求 5）：聚焦自己島時左上角可展開面板 ─────────────────────────────
  Widget _buildSelfStatusPanel() {
    final mine = _myGroup;
    final slots = mine?.slots.values.toList() ?? const <FightSlot>[];
    final intact = [for (final s in slots) if (!s.broken) s];
    final broken = [for (final s in slots) if (s.broken) s];
    final hp = mine?.hp(_heritageId) ?? 0;
    final hpMax = mine?.hpMax(_heritageId) ?? 0;
    final ratio = hpMax == 0 ? 0.0 : (hp / hpMax).clamp(0.0, 1.0);
    final group = context.read<AppState>().currentGroup;
    final expanded = _selfStatusExpanded;
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xEB1F2225),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x556FC36F)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標頭（點擊展開 / 收合）。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => _selfStatusExpanded = !_selfStatusExpanded),
            child: Row(
              children: [
                AvatarFrame(size: 44, imageUrl: group?.avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mine?.displayName ?? '我方古蹟',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const Text(
                        '查看詳細狀況',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          // 展開內容：血量 + 完好 / 已損毀物件。
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? _selfStatusBody(hp, hpMax, ratio, intact, broken)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _selfStatusBody(
    int hp,
    int hpMax,
    double ratio,
    List<FightSlot> intact,
    List<FightSlot> broken,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(180.0, _viewport.height * 0.6),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),
            // 血量條。
            Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF6FC36F),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(height: 12, color: const Color(0x22FFFFFF)),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: 12,
                            color: const Color(0xFF6FC36F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$hp / $hpMax',
                  style: const TextStyle(
                    color: Color(0xFFE7CF9A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _statusSection(
              '完好物件',
              intact.length,
              const Color(0xFF6FC36F),
              intact,
              broken: false,
            ),
            const SizedBox(height: 16),
            _statusSection(
              '已損毀物件',
              broken.length,
              const Color(0xFFE06A5A),
              broken,
              broken: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusSection(
    String title,
    int count,
    Color accent,
    List<FightSlot> slots, {
    required bool broken,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 16,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: accent,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              broken ? '目前沒有損毀的物件，守得很好！' : '沒有完好的物件',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final s in slots) _statusChip(s, accent, broken)],
          ),
      ],
    );
  }

  Widget _statusChip(FightSlot s, Color accent, bool broken) {
    final comp = componentById(_heritageId, s.type);
    final name = comp?.name ?? '元件';
    final level = comp?.level ?? 1;
    final img = comp == null
        ? null
        : (broken ? comp.brokenImagePath : comp.imagePath);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF231F19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: img == null
                ? const Icon(Icons.broken_image_outlined, color: Colors.white24)
                : Opacity(
                    opacity: broken ? 0.6 : 1,
                    child: Image.asset(
                      img,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white24,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  broken ? '已損毀' : 'Lv.$level',
                  style: TextStyle(color: accent, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
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
            Image.asset(
              'assets/icons/times_up.png',
              width: 320,
              errorBuilder: (_, _, _) => const Text(
                '時間到',
                style: TextStyle(color: Colors.white, fontSize: 40),
              ),
            ),
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
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Center(
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 620),
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            decoration: BoxDecoration(
              color: const Color(0xF21F2225),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x55D4A843)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '攻防戰結果',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: board.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            '暫無結果',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: board.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _leaderRow(board[i]),
                        ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: _goldButton(label: '結束遊戲', onTap: _confirmEnd),
                ),
              ],
            ),
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
          color: e.rank == 1
              ? const Color(0xFFD4A843)
              : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${e.rank}',
              style: TextStyle(
                color: e.rank == 1 ? const Color(0xFFD4A843) : Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
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
            child: Text(
              e.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            children: [
              Text(
                e.hpMax > 0 ? '${e.hp} / ${e.hpMax}' : '${e.hp}',
                style: const TextStyle(
                  color: Color(0xFFE7CF9A),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '血量',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
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
                  valueColor: AlwaysStoppedAnimation(Color(0xFF2A1A0A)),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF2A1A0A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }

  Widget _resultButton(
    String label,
    VoidCallback onTap, {
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFE8CBA8) : const Color(0x559B8066),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF7B5C49), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2A1A0A),
            fontSize: 15,
            letterSpacing: 2,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── 互動進入點（點島聚焦 / 補給站）────────────────────────────────────────────────
  // 「我的古蹟」選單 → 鏡頭聚焦自己島（左上顯示戰況面板，需求 5）。
  void _onTapSelf() {
    final mine = _myGroup;
    if (mine == null) {
      _toast('尚未取得我方古蹟資料');
      return;
    }
    _focusGroup(mine);
  }

  // 文資補給：選單按鈕與地圖補給島點擊等價（需求 6）——未聚焦先聚焦補給島、已聚焦則開修復面板。
  void _onTapSupply() {
    if (_supplyFocused) {
      _openSupplyPanel();
    } else {
      _focusSupply();
    }
  }

  void _openGroupOverview() {
    setState(() => _panelOpen = false);
    _panelCtrl.reverse();
    context.push('/group-overview');
  }

  void _logout() {
    setState(() => _panelOpen = false);
    _panelCtrl.reverse();
    context.read<AppState>().logout();
  }

  void _openSupplyPanel() {
    setState(() {
      _panelOpen = false;
      _supplyFocused = false;
      _supplyOpen = true;
      _attackTarget = null;
    });
    _panelCtrl.reverse();
  }

  void _closeSupply() => setState(() => _supplyOpen = false);
  void _closeOutcome() => setState(() => _outcome = null);

  // ── 攻擊 / 修復：確認 → target 取題 → 作答 → 結果 ───────────────────────────────
  void _beginAttack(
    FightGroup enemy,
    FightSlot slot,
    ComponentModel comp,
    Rect sceneRect,
  ) {
    if (_timeUp) return;
    // 只在「首次」進攻擊（從島嶼視角點第一個部件）時記住要還原的島嶼視角；
    // 若已在攻擊確認中又改點別的部件（A→B），不要把當前已放大的部件視角誤存為還原點，
    // 否則取消時會跑回前一個部件而非島嶼正中（需求 4）。
    if (_attackTarget == null) {
      _attackReturnTransform = _tc.value.clone();
    }
    setState(() {
      _attackTarget = _AttackTarget(
        target: enemy,
        slot: slot,
        component: comp,
        sceneRect: sceneRect,
      );
    });
    _animateTo(_focusComponentMatrix(sceneRect));
  }

  void _cancelAttack() {
    if (_attackTarget == null) return;
    setState(() => _attackTarget = null);
    _animateTo(_attackReturnTransform);
  }

  Future<void> _confirmAttackTarget() async {
    final target = _attackTarget;
    if (target == null) return;
    setState(() => _attackTarget = null);
    await _attemptAttack(target.target, target.slot);
  }

  Future<void> _attemptAttack(FightGroup enemy, FightSlot slot) async {
    final name = componentById(_heritageId, slot.type)?.name ?? '元件';
    if (slot.broken) {
      _toast('「$name」已被攻破');
      return;
    }
    if (slot.attackBlocked) {
      _toast('這格你已答錯過，需等對方修復後才能再攻擊');
      return;
    }
    await _runTarget(target: enemy, slot: slot, repair: false, compName: name);
  }

  Future<void> _attemptRepair(FightSlot slot) async {
    final mine = _myGroup;
    if (mine == null) return;
    final name = componentById(_heritageId, slot.type)?.name ?? '元件';
    final ok = await _confirm(
      title: '修復「$name」',
      body: '將依此部件難度出一題，答對即可修復並重新綁定題目。準備好了嗎？',
      confirmLabel: '開始修復',
      accent: const Color(0xFF6FC36F),
    );
    if (ok != true) return;
    await _runTarget(target: mine, slot: slot, repair: true, compName: name);
  }

  /// 開 target session 取題；接住 403（被禁打 / 狀態不允許）等錯誤。
  Future<void> _runTarget({
    required FightGroup target,
    required FightSlot slot,
    required bool repair,
    required String compName,
  }) async {
    if (!mounted || _timeUp) return; // 確認對話框期間時間到 → 不再開新 session
    final quiz = context.read<QuizService>();
    setState(() {
      _supplyOpen = false;
      _opening = true;
      _attackTarget = null;
    });
    try {
      final q = await quiz.targetQuestion(
        targetUserId: target.userId,
        targetSlotId: slot.slotId,
      );
      if (!mounted) return;
      setState(() {
        _opening = false;
        _answerQ = q;
        _answerCtx = _TargetCtx(
          repair: repair,
          targetUserId: target.userId,
          slotId: slot.slotId,
          targetName: target.displayName,
          compName: compName,
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      if (e.statusCode == 403) {
        _toast(repair ? '目前無法修復這個部件' : '這格你已答錯過，需等對方修復後才能再攻擊');
      } else if (e.statusCode == 400) {
        _toast('目標狀態已改變，請重新選擇');
      } else if (e.statusCode == 404) {
        _toast('找不到目標，請重新整理');
      } else {
        _toast('無法開始（${e.statusCode}）');
      }
      unawaited(_refreshGroups());
    } catch (_) {
      if (!mounted) return;
      setState(() => _opening = false);
      _toast('連線失敗，請再試一次');
    }
  }

  void _onAnswerResult(QuizResult res) {
    final ctx = _answerCtx;
    // 後端 target session：correct 且 success==true 才代表真的攻破 / 修復成立。
    final success = res.correct && res.success == true;
    setState(() {
      _answerQ = null;
      _answerCtx = null;
      _outcome = _Outcome(
        repair: ctx?.repair ?? false,
        success: success,
        compName: ctx?.compName ?? '元件',
      );
    });
    // 成功時同步本機快取（Mock：實際改變世界地圖；Api：no-op，靠下方 refetch + WS 反映）。
    if (success && ctx != null) {
      context.read<FightService>().localApply(
        targetUserId: ctx.targetUserId,
        slotId: ctx.slotId,
        broken: !ctx.repair,
      );
    }
    // 反映後端最新狀態（被攻破 / 已修復）。
    unawaited(_refreshGroups());
  }

  void _onAnswerAbort() {
    setState(() {
      _answerQ = null;
      _answerCtx = null;
    });
    _toast('作答送出失敗，題目可能已逾時，請重新挑戰');
  }

  Future<void> _refreshGroups() async {
    final fight = context.read<FightService>();
    try {
      final groups = await fight.fetchAllGroups(
        selfUserId: _selfId,
        heritageId: _heritageId,
      );
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (_) {}
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required Color accent,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF23201B),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF2A2420),
        ),
      );
  }

  Widget _buildAttackConfirm() {
    final target = _attackTarget;
    if (target == null) return const SizedBox.shrink();
    const boxW = 286.0;
    return AnimatedBuilder(
      animation: _tc,
      builder: (_, _) {
        final cr = _screenRect(target.sceneRect, _tc.value);
        double left = cr.left - boxW - 18;
        if (left < 8) left = cr.right + 18;
        left = left.clamp(8.0, math.max(8.0, _viewport.width - boxW - 8));
        return Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: boxW,
          child: Center(child: _attackConfirmBox(target)),
        );
      },
    );
  }

  Widget _attackConfirmBox(_AttackTarget target) {
    final comp = target.component;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xF21F2225),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FF6B5E)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '攻打原料',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '確定要攻打「${comp.name}」嗎？',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x33FF6B5E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FF6B5E)),
            ),
            child: Text(
              '題目難度 Lv.${comp.level}',
              style: const TextStyle(
                color: Color(0xFFFFC7B8),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelAttack,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _confirmAttackTarget,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0x33FF3B30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text(
                  '攻 打',
                  style: TextStyle(
                    color: Color(0xFFFF6B5E),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 文資補給站（修復）─────────────────────────────────────────────────────────
  Widget _buildSupplyPanel() {
    final mine = _myGroup;
    final broken = mine == null
        ? const <FightSlot>[]
        : mine.brokenSlots.toList();
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xF20E0A06),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Image.asset(
                        'assets/icons/buttons/supply_station_btn.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '文資補給站',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _closeSupply,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '選擇要修復的損毀部件，答對該難度題目即可修復',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: broken.isEmpty
                    ? const Center(
                        child: Text(
                          '目前沒有損毀的部件，繼續守住古蹟！',
                          style: TextStyle(color: Colors.white54, fontSize: 15),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: broken.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _repairCard(broken[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _repairCard(FightSlot s) {
    final comp = componentById(_heritageId, s.type);
    final name = comp?.name ?? '元件';
    final level = comp?.level ?? 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF231F19),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Opacity(
              opacity: 0.45,
              child: comp == null
                  ? const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white30,
                    )
                  : Image.asset(
                      comp.imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white30,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '難度 Lv.$level ・已損毀',
                  style: const TextStyle(
                    color: Color(0xFFE06A5A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _attemptRepair(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6FC36F),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '修復',
                style: TextStyle(
                  color: Color(0xFF11250F),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 作答 / 結果 / 取題轉圈 ─────────────────────────────────────────────────────
  Widget _buildAnswerSheet() {
    final ctx = _answerCtx!;
    return FightQuizSheet(
      question: _answerQ!,
      title: ctx.repair ? '修復古蹟' : '攻打 ${ctx.targetName}',
      subtitle: ctx.repair
          ? '答對即可修復「${ctx.compName}」'
          : '答對即可攻破「${ctx.compName}」',
      accent: ctx.repair ? const Color(0xFF6FC36F) : const Color(0xFFE06A5A),
      onSubmit: (a) => context.read<QuizService>().submitAnswer(a),
      onResult: _onAnswerResult,
      onAbort: _onAnswerAbort,
    );
  }

  Widget _buildOutcome(_Outcome o) {
    final asset = o.repair
        ? (o.success
              ? 'assets/icons/supply_successful.png'
              : 'assets/icons/supply_fail.png')
        : (o.success
              ? 'assets/icons/attack_successful.png'
              : 'assets/icons/attack_fail.png');
    final String headline;
    if (o.repair) {
      headline = o.success ? '修復成功！' : '修復失敗';
    } else {
      headline = o.success ? '攻擊成功！' : '攻擊失敗';
    }
    final sub = o.success
        ? (o.repair ? '「${o.compName}」已修復' : '已攻破「${o.compName}」')
        : (o.repair ? '「${o.compName}」尚未修復，再試一次' : '答錯了，需等對方修復後才能再打這格');
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                asset,
                width: 620,
                errorBuilder: (_, _, _) => Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xF2CDB590),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 16,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2A1A0A),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6E4D45),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          sub,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFE7B2),
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _resultButton('繼續', _closeOutcome, filled: true),
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

  Widget _buildOpening() {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0x99000000),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFD4A843)),
        ),
      ),
    );
  }
}

/// 一次攻擊 / 修復作答的目標脈絡（給結果畫面、標題與 Mock 同步用）。
class _TargetCtx {
  final bool repair;
  final int targetUserId;
  final int slotId;
  final String targetName;
  final String compName;
  const _TargetCtx({
    required this.repair,
    required this.targetUserId,
    required this.slotId,
    required this.targetName,
    required this.compName,
  });
}

class _AttackTarget {
  final FightGroup target;
  final FightSlot slot;
  final ComponentModel component;
  final Rect sceneRect;

  const _AttackTarget({
    required this.target,
    required this.slot,
    required this.component,
    required this.sceneRect,
  });
}

/// 攻擊 / 修復結果。
class _Outcome {
  final bool repair;
  final bool success;
  final String compName;
  const _Outcome({
    required this.repair,
    required this.success,
    required this.compName,
  });
}

/// 一則「被攻打」小彈窗（id 供逾時移除比對；附該元件破損圖路徑）。
class _AttackPop {
  final int id;
  final String name;
  final String brokenImagePath;
  const _AttackPop(this.id, this.name, this.brokenImagePath);
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
                    fontWeight: FontWeight.w700,
                  ),
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
                Text(
                  '$hp / $hpMax',
                  style: const TextStyle(
                    color: Color(0xFFE7CF9A),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
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
