import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/avatar_frame.dart';
import '../../core/widgets/loading_screen.dart';
import '../../data/component_data.dart';
import '../../data/heritage_data.dart';
import '../../data/models/component_model.dart';
import '../../data/models/heritage_model.dart';
import '../../data/models/heritage_slot.dart';
import '../../data/slot_data.dart';
import '../../state/app_state.dart';
import '../../state/heritage_board_controller.dart';
import 'package:go_router/go_router.dart';
import 'heritage_view_geometry.dart';
import 'widgets/framed_component_tile.dart';
import 'widgets/heritage_info_dialog.dart';
import 'widgets/component_codex_dialog.dart';

class MyHeritageScreen extends StatefulWidget {
  const MyHeritageScreen({super.key});

  @override
  State<MyHeritageScreen> createState() => _MyHeritageScreenState();
}

class _MyHeritageScreenState extends State<MyHeritageScreen>
    with TickerProviderStateMixin {
  static const double _panelWidth = 220.0;
  static const double _handleWidth = 108.0; // 收合時的寬度（頭像 + chevron）
  static const double _btnIconSize = 54.0;
  // 編輯底部「原料庫 / 物品欄」面板底色（暖色深木調）。
  static const Color _panelBg = Color(0xF03A332E);

  bool _isPanelOpen = false;
  bool _editMode = false;
  bool _assetsPrecached = false; // 資源只預載一次
  bool _loading = true; // 預載期間蓋上載入畫面
  bool _loadingMounted = true; // 載入畫面淡出後才從樹上移除
  ComponentModel? _dragging; // 編輯模式下拖曳中的原料
  int? _level = 1; // 底部背包等級篩選（null = 顯示全部原料）

  // 左上角面板選單按鈕圖：先 precache 進 ImageCache，面板每次展開時
  // Image.asset 直接命中快取，不會再有逐張解碼造成的閃爍。
  static const List<String> _menuBtnAssets = [
    'assets/icons/buttons/heritages_info_btn.png',
    'assets/icons/buttons/edit_heritages_btn.png',
    'assets/icons/buttons/component_collection_btn.png',
    'assets/icons/buttons/fight_btn.png',
  ];

  late final AnimationController _introCtrl;
  late final AnimationController _blink;
  late final AnimationController _viewAnim; // 拆卸時的鏡頭推近/還原動畫
  late final AnimationController _panelCtrl; // 左上角面板展開/收合
  late final Animation<double> _panelCurve;
  Matrix4Tween? _viewTween;
  final TransformationController _tc = TransformationController();
  final ScrollController _invScroll = ScrollController(); // 物品欄水平捲動
  Size _viewport = Size.zero;

  // 拆卸確認狀態（非 null = 正在詢問是否拆下該 slot 的原料）
  HeritageSlot? _confirmSlot;
  ComponentModel? _confirmComp;
  Matrix4 _savedTransform = Matrix4.identity();

  HeritageModel get _heritage => mockHeritages.firstWhere(
    (h) => h.status == HeritageStatus.assigned,
    orElse: () => mockHeritages.first,
  );

  @override
  void initState() {
    super.initState();
    // intro 動畫改在資源預載完成、載入畫面淡出時才播放。
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _panelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelCurve = CurvedAnimation(
      parent: _panelCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _viewAnim =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 350),
        )..addListener(() {
          final tw = _viewTween;
          if (tw != null) {
            _tc.value = tw.transform(
              Curves.easeInOut.transform(_viewAnim.value),
            );
          }
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final group = context.read<AppState>().currentGroup;
      if (group != null) {
        context.read<HeritageBoardController>().bind(
          groupId: group.id,
          heritageId: _heritage.id,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsPrecached) return;
    _assetsPrecached = true;
    _preloadThenReveal();
  }

  /// 在載入畫面後一次預載本頁所有重資源（背景 / 古蹟主圖 / 編輯格線 / 選單與功能
  /// 按鈕 / 卡框 / 全部原料圖），全部解碼進 ImageCache 後才淡出載入畫面，進場與
  /// 之後切換編輯模式都直接命中快取、不再逐張解碼造成卡頓或閃爍。
  Future<void> _preloadThenReveal() async {
    final paths = <String>[
      ..._menuBtnAssets,
      'assets/images/bg_view.png',
      'assets/images/edit_grid.png',
      'assets/icons/buttons/supply_station_btn.png',
      'assets/images/heritages/${_heritage.id}/main.png',
      for (final lv in const [1, 2, 3]) levelFrameImagePath(lv),
      for (final c in componentsOf(_heritage.id)) c.imagePath,
    ];
    // 先同步建立所有 precache future（在任何 await 之前用 context），缺圖以
    // onError 吞掉避免卡住；再加一段最短停留時間，避免快取已熱時載入畫面一閃而過。
    final jobs = <Future<void>>[
      for (final p in paths)
        precacheImage(AssetImage(p), context, onError: (_, _) {}),
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ];
    await Future.wait(jobs);
    if (!mounted) return;
    setState(() => _loading = false);
    _introCtrl.forward();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _blink.dispose();
    _viewAnim.dispose();
    _panelCtrl.dispose();
    _tc.dispose();
    _invScroll.dispose();
    super.dispose();
  }

  // ── mode / actions ──────────────────────────────────────────────────────────

  void _togglePanel() {
    setState(() => _isPanelOpen = !_isPanelOpen);
    if (_isPanelOpen) {
      _panelCtrl.forward();
    } else {
      _panelCtrl.reverse();
    }
  }

  void _enterEdit() {
    setState(() {
      _editMode = true;
      _isPanelOpen = false;
    });
    _panelCtrl.reverse();
  }

  void _exitEdit() => setState(() {
    _editMode = false;
    _dragging = null;
  });

  void _setDragging(ComponentModel? c) {
    if (_dragging?.id != c?.id) setState(() => _dragging = c);
  }

  void _showInfo() => showDialog(
    context: context,
    builder: (_) => HeritageInfoDialog(heritage: _heritage),
  );

  void _openCodex() => showDialog(
    context: context,
    builder: (_) => ComponentCodexDialog(heritageId: _heritage.id),
  );

  void _logout() => context.read<AppState>().logout();

  /// 開始拆卸確認：記住目前鏡頭、推近聚焦該 slot（置中、留左側空間給確認框），
  /// 並讓該原料閃爍。確認框由 build 依當下 transform 畫在原料左側。
  void _beginUninstall(HeritageSlot slot, ComponentModel comp, Rect sceneRect) {
    if (_confirmSlot != null) return;
    _savedTransform = _tc.value.clone();
    setState(() {
      _confirmSlot = slot;
      _confirmComp = comp;
    });
    _animateTo(_focusMatrix(sceneRect));
  }

  Future<void> _endUninstall({required bool remove}) async {
    final slot = _confirmSlot;
    setState(() {
      _confirmSlot = null;
      _confirmComp = null;
    });
    if (remove && slot != null) {
      await context.read<HeritageBoardController>().removeAt(slot.id);
    }
    _animateTo(_savedTransform);
  }

  void _animateTo(Matrix4 target) {
    _viewTween = Matrix4Tween(begin: _tc.value.clone(), end: target);
    _viewAnim.forward(from: 0);
  }

  /// 推近矩陣：把 sceneRect 放大置中（依寬度），讓原料約占畫面寬 26%。
  Matrix4 _focusMatrix(Rect sceneRect) {
    final vp = _viewport;
    final s = ((vp.width * 0.26) / sceneRect.width).clamp(1.6, 6.0);
    final centerTarget = Offset(vp.width * 0.5, vp.height * 0.5);
    final off = centerTarget - sceneRect.center * s;
    return Matrix4.identity()
      ..translateByDouble(off.dx, off.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// scene 座標 → 螢幕座標（僅含等比例縮放 + 平移）。
  Offset _toScreen(Offset scene, Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    return Offset(t.x + s * scene.dx, t.y + s * scene.dy);
  }

  Rect _screenRect(Rect sceneRect, Matrix4 m) => Rect.fromPoints(
    _toScreen(sceneRect.topLeft, m),
    _toScreen(sceneRect.bottomRight, m),
  );

  // ── zoom controls ───────────────────────────────────────────────────────────

  void _zoomBy(double factor) {
    if (_viewport == Size.zero) return;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final scene = _tc.toScene(center);
    final current = _tc.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 8.0);
    final f = target / current;
    if ((f - 1).abs() < 1e-3) return;
    _tc.value = _tc.value.clone()
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
  }

  void _recenter() => _tc.value = Matrix4.identity();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final board = context.watch<HeritageBoardController>();

    final confirming = _confirmSlot != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (confirming) {
          _endUninstall(remove: false);
        } else if (_editMode) {
          _exitEdit();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1F2225),
        body: Stack(
          children: [
            _buildMapView(board),
            SafeArea(
              child: Stack(
                children: [
                  if (!_editMode)
                    _buildPanel(state)
                  else if (!confirming)
                    _buildEditTopBar(),
                  if (!confirming) _buildZoomControls(),
                ],
              ),
            ),
            if (!_editMode)
              Positioned(right: 24, bottom: 24, child: _buildNameWatermark()),
            if (_editMode && !confirming)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(board),
              ),
            if (confirming) _buildUninstallConfirm(),
            if (!_editMode)
              AnimatedBuilder(
                animation: _introCtrl,
                builder: (_, _) {
                  if (_introCtrl.isCompleted) return const SizedBox.shrink();
                  return _buildIntroOverlay(state);
                },
              ),
            // 載入畫面：蓋在最上層；預載完成後淡出再從樹上移除。
            if (_loadingMounted)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _loading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  onEnd: () {
                    if (!_loading && _loadingMounted) {
                      setState(() => _loadingMounted = false);
                    }
                  },
                  child: AbsorbPointer(
                    absorbing: _loading,
                    child: const LoadingScreen(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Uninstall confirmation (focuses the component, box on its left) ─────────

  Widget _buildUninstallConfirm() {
    final slot = _confirmSlot;
    final comp = _confirmComp;
    if (slot == null || comp == null) return const SizedBox.shrink();
    const boxW = 268.0;
    return AnimatedBuilder(
      animation: _tc,
      builder: (_, _) {
        final main = HeritageViewGeometry.mainRect(_viewport);
        final cr = _screenRect(
          HeritageViewGeometry.slotRect(slot, main),
          _tc.value,
        );
        double left = cr.left - boxW - 18;
        if (left < 8) left = cr.right + 18; // 左側放不下 → 改放右側
        left = left.clamp(8.0, _viewport.width - boxW - 8);
        final box = _confirmBox(comp);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: boxW,
              child: Center(child: box),
            ),
          ],
        );
      },
    );
  }

  Widget _confirmBox(ComponentModel comp) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xF21F2225),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
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
            '拆下原料',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '確定要拆下「${comp.name}」嗎？\n拆下後會放回背包。',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _endUninstall(remove: false),
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
                onPressed: () => _endUninstall(remove: true),
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
                  '拆 下',
                  style: TextStyle(
                    color: Color(0xFFFF6B5E),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Interactive map (view + edit share the same transform) ──────────────────

  Widget _buildMapView(HeritageBoardController board) {
    final slots = slotsOf(_heritage.id);
    final dragging = _dragging != null;
    final locked = dragging || _confirmSlot != null;
    // 額外可拖曳範圍：螢幕短邊的 40%。此值同時決定 bg_view / edit_grid 的大小
    //（兩者鋪滿「viewport ± dragMargin」這個 scene，cover 後 scene 越大圖越大）。
    // 想讓背景 / 格線再小一點就調低此係數（連帶可拖曳範圍也會略縮）。
    final dragMargin = MediaQuery.sizeOf(context).shortestSide * 0.4;
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 1.0,
      maxScale: 8.0,
      boundaryMargin: EdgeInsets.all(dragMargin),
      panEnabled: !locked,
      scaleEnabled: !locked,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _viewport = viewport;
          final main = HeritageViewGeometry.mainRect(viewport);
          // 整個可拖曳範圍（viewport 各邊各擴張 dragMargin）。背景 / 格線 / 變暗
          // 都鋪滿此範圍，拖曳到邊緣時才不會露出底色。
          final scene = Rect.fromLTRB(
            -dragMargin,
            -dragMargin,
            viewport.width + dragMargin,
            viewport.height + dragMargin,
          );
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _editMode
                ? (d) => _handleMapTap(d.localPosition, main, board, slots)
                : null,
            child: Stack(
              fit: StackFit.expand,
              // main.png 為 viewport 寬 × 0.65 的正方形，在橫向平板上邊長常大於
              // viewport 高度，上下會超出 Stack 範圍。預設 hardEdge 會在套用
              // InteractiveViewer 變換「之前」就把超出部分裁掉，導致拖曳也看不到。
              // 改為 none → 完整繪製，靠 InteractiveViewer 外層裁切控制可視範圍。
              clipBehavior: Clip.none,
              children: [
                // 背景鋪滿整個可拖曳範圍（非僅 viewport），拖曳到邊緣不露底。
                Positioned.fromRect(
                  rect: scene,
                  child: Image.asset(
                    'assets/images/bg_view.png',
                    fit: BoxFit.cover,
                  ),
                ),
                // bg_view 與 main 之間的 edit_grid：永遠掛載（隨頁面預載解碼），
                // 靠 opacity 切換顯示，進入編輯模式時不必重新解碼、不會卡頓。
                Positioned.fromRect(
                  rect: scene,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _editMode ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Image.asset(
                        'assets/images/edit_grid.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: main,
                  child: Image.asset(
                    'assets/images/heritages/${_heritage.id}/main.png',
                    fit: BoxFit.fill,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                // 編輯模式整體變暗：鋪滿整個可拖曳範圍（已放置原料畫在此層之上 → 較亮）
                if (_editMode)
                  Positioned.fromRect(
                    rect: scene,
                    child: const IgnorePointer(
                      child: ColoredBox(color: Color(0x73000000)),
                    ),
                  ),
                // 已放置原料（隨 main 一起縮放/平移）
                for (final s in slots)
                  if (board.itemAt(s.id) != null)
                    _placedComponent(
                      HeritageViewGeometry.slotRect(s, main),
                      viewport,
                      componentById(_heritage.id, board.itemAt(s.id)!)!,
                      blinking: _confirmSlot?.id == s.id,
                    ),
                // 編輯且拖曳中：可放置 slot 的 highlight + 拖放目標
                if (_editMode && dragging)
                  for (final s in slots)
                    if (!board.isSlotFilled(s.id) &&
                        board.canPlace(_dragging!, s.id))
                      _dropTarget(
                        s,
                        HeritageViewGeometry.slotRect(s, main),
                        board,
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleMapTap(
    Offset local,
    Rect main,
    HeritageBoardController board,
    List<HeritageSlot> slots,
  ) {
    if (_confirmSlot != null) return; // 確認中，忽略地圖點擊
    for (final s in slots) {
      final itemId = board.itemAt(s.id);
      if (itemId == null) continue;
      final rect = HeritageViewGeometry.slotRect(s, main);
      if (rect.contains(local)) {
        final comp = componentById(_heritage.id, itemId);
        if (comp != null) _beginUninstall(s, comp, rect);
        return;
      }
    }
  }

  /// 已放置原料：以 slot 寬度等比例放大、底部對齊 slot 底部；高度可超出 slot 上緣。
  /// [blinking] = true 時（拆卸確認中）亮暗閃爍。
  Widget _placedComponent(
    Rect rect,
    Size viewport,
    ComponentModel comp, {
    bool blinking = false,
  }) {
    Widget img = Image.asset(
      comp.imagePath,
      width: rect.width,
      fit: BoxFit.fitWidth,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (blinking) {
      img = AnimatedBuilder(
        animation: _blink,
        builder: (_, child) =>
            Opacity(opacity: 0.35 + 0.65 * _blink.value, child: child),
        child: img,
      );
    }
    return Positioned(
      left: rect.left,
      width: rect.width,
      bottom: viewport.height - rect.bottom,
      child: IgnorePointer(child: img),
    );
  }

  Widget _dropTarget(HeritageSlot s, Rect rect, HeritageBoardController board) {
    return Positioned.fromRect(
      rect: rect,
      child: DragTarget<ComponentModel>(
        onWillAcceptWithDetails: (d) => board.canPlace(d.data, s.id),
        onAcceptWithDetails: (d) => board.place(d.data, s.id),
        builder: (_, candidate, _) {
          final hovering = candidate.isNotEmpty;
          return AnimatedBuilder(
            animation: _blink,
            builder: (_, _) {
              final a = hovering ? 0.85 : (0.30 + 0.45 * _blink.value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A843).withValues(alpha: a * 0.35),
                  border: Border.all(
                    color: const Color(0xFFD4A843).withValues(alpha: a),
                    width: hovering ? 3 : 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4A843).withValues(alpha: a * 0.5),
                      blurRadius: 12,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Zoom controls (both modes) ──────────────────────────────────────────────

  Widget _buildZoomControls() {
    return Positioned(
      right: 16,
      // 編輯模式下的物品欄較高 → 縮放鈕上移，並與左移的等級切鈕並排不互蓋。
      bottom: _editMode ? 252 : 90,
      child: Column(
        children: [
          _zoomBtn(Icons.add, () => _zoomBy(1.25)),
          const SizedBox(height: 8),
          _zoomBtn(Icons.remove, () => _zoomBy(0.8)),
          const SizedBox(height: 8),
          _zoomBtn(Icons.center_focus_strong, _recenter),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xAA1F2225),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  // ── Edit-mode top bar ───────────────────────────────────────────────────────

  Widget _buildEditTopBar() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          _editPill(
            onTap: _exitEdit,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text('返回', style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          const Spacer(),
          _editPill(
            onTap: () => context.push('/slot-editor/${_heritage.id}'),
            child: const Icon(Icons.grid_on, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _editPill({required Widget child, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC1F2225),
            borderRadius: BorderRadius.circular(22),
          ),
          child: child,
        ),
      );

  // ── Edit-mode bottom bar：原料庫(獨立左側) + 物品欄(等級切鈕在右上角) ──────────

  Widget _buildBottomBar(HeritageBoardController board) {
    final items = componentsOf(_heritage.id)
        .where(
          (c) => (_level == null || c.level == _level) && board.qty(c.id) > 0,
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 等級切鈕移到物品欄「外面、右上方」；右側留白讓開縮放按鈕。
            Padding(
              padding: const EdgeInsets.only(right: 50),
              child: _levelToggles(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 202,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _codexBox(board.unusedCount),
                  const SizedBox(width: 14),
                  Expanded(child: _itemPanel(board, items)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 原料庫：獨立左側方塊，右上角徽章顯示未使用原料數
  Widget _codexBox(int unused) {
    return GestureDetector(
      onTap: _openCodex,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 158,
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white24),
            ),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Image.asset(
                    'assets/icons/buttons/supply_station_btn.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFD4A843),
                      size: 66,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '原料庫',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          // 未使用原料數徽章
          Positioned(
            top: -10,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8DCC0),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF8B6914), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '$unused',
                style: const TextStyle(
                  color: Color(0xFF3A2E10),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 物品欄：左右箭頭捲動，中間可拖曳原料（等級切鈕已移至面板外右上方）
  Widget _itemPanel(HeritageBoardController board, List<ComponentModel> items) {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: Row(
        children: [
          _scrollArrow(right: false),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _level == null
                          ? '目前沒有可佈置的原料\n（採集後會出現在這裡）'
                          : 'Lv.$_level 沒有可佈置的原料\n（採集後會出現在這裡）',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _invScroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (_, i) =>
                        _draggableItem(items[i], board.qty(items[i].id)),
                  ),
          ),
          _scrollArrow(right: true),
        ],
      ),
    );
  }

  Widget _levelToggles() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xCC1F2225),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _levelToggle(1),
        const SizedBox(width: 10),
        _levelToggle(2),
        const SizedBox(width: 10),
        _levelToggle(3),
      ],
    ),
  );

  Widget _levelToggle(int level) {
    final on = _level == level;
    return GestureDetector(
      // 再點一次目前選取的等級 → 取消篩選（顯示全部原料）。
      onTap: () => setState(() => _level = on ? null : level),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: on ? 1.0 : 0.4,
              child: Image.asset(
                levelFrameImagePath(level),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (on)
              const Positioned(
                right: -2,
                top: -2,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFF2E7D32),
                  child: Icon(Icons.check, size: 13, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scrollArrow({required bool right}) {
    return GestureDetector(
      onTap: () {
        if (!_invScroll.hasClients) return;
        final max = _invScroll.position.maxScrollExtent;
        final target = (_invScroll.offset + (right ? 1 : -1) * 280).clamp(
          0.0,
          max,
        );
        _invScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      },
      child: SizedBox(
        width: 46,
        child: Icon(
          right ? Icons.arrow_right : Icons.arrow_left,
          color: const Color(0xFFD4A843),
          size: 46,
        ),
      ),
    );
  }

  Widget _draggableItem(ComponentModel comp, int qty) {
    const cardSize = 150.0;
    final card = _InventoryCard(component: comp, quantity: qty);
    return Draggable<ComponentModel>(
      data: comp,
      // 只認垂直拖曳（往上放到地圖）；左右拖讓給 ListView 捲動瀏覽。
      affinity: Axis.vertical,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => _setDragging(comp),
      onDragEnd: (_) => _setDragging(null),
      onDraggableCanceled: (_, _) => _setDragging(null),
      feedback: Transform.translate(
        offset: const Offset(-cardSize / 2, -cardSize / 2),
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: cardSize,
            height: cardSize,
            child: Image.asset(comp.imagePath, fit: BoxFit.contain),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }

  // ── Left panel (view mode) ──────────────────────────────────────────────────

  Widget _buildPanel(AppState state) {
    final group = state.currentGroup;
    final avatarPath = group?.avatarUrl;
    final groupName = group?.name ?? '';
    final groupId = group?.id;

    return Positioned(
      left: 12,
      top: 12,
      child: AnimatedBuilder(
        animation: _panelCurve,
        builder: (_, _) =>
            _panelSurface(_panelCurve.value, avatarPath, groupName, groupId),
      ),
    );
  }

  /// 依展開進度 [t]（0=收合，1=展開）繪製左上角面板：頭像固定不動，背景/邊框淡入、
  /// 寬度展開；下方選單以「高度展開 + 淡入」揭露；頭像右側收合時為 chevron、
  /// 展開時為組名（前後半段交叉淡入）。
  Widget _panelSurface(
    double t,
    String? avatarPath,
    String groupName,
    int? groupId,
  ) {
    final tc = t.clamp(0.0, 1.0);
    return Container(
      width: _handleWidth + (_panelWidth - _handleWidth) * tc,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Color.fromRGBO(31, 34, 37, 0.92 * tc),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24 * tc)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _togglePanel,
                child: AvatarFrame(size: 52, imageUrl: avatarPath),
              ),
              const SizedBox(width: 10),
              Expanded(child: _panelHeaderTrailing(tc, groupName, groupId)),
            ],
          ),
          // 下方選單：高度由 0→滿、同時淡入。永遠保持建構（收合時高度 0、不透明度 0
          // → 既不顯示、零高度的 ClipRect 也吃掉點擊），讓按鈕圖只在首次掛載時解碼一次，
          // 不再每次展開都重新掛載 Image.asset 而閃爍。
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

  /// 頭像右側：收合時顯示可點開的 chevron，展開時顯示組名 / GROUP 編號。
  Widget _panelHeaderTrailing(double t, String groupName, int? groupId) {
    if (t < 0.5) {
      return GestureDetector(
        onTap: _togglePanel,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: (1 - t * 2).clamp(0.0, 1.0),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.chevron_right, color: Colors.white54, size: 22),
          ),
        ),
      );
    }
    return Opacity(
      opacity: ((t - 0.5) * 2).clamp(0.0, 1.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groupName.isNotEmpty)
            Text(
              groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          if (groupId != null)
            Text(
              'GROUP $groupId',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _togglePanel,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white38,
                size: 20,
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 6),
        _menuBtn(
          'assets/icons/buttons/heritages_info_btn.png',
          '古蹟資訊',
          onTap: _showInfo,
        ),
        _menuBtn(
          'assets/icons/buttons/edit_heritages_btn.png',
          '編輯古蹟',
          onTap: _enterEdit,
        ),
        _menuBtn(
          'assets/icons/buttons/component_collection_btn.png',
          '資源採集',
          onTap: null,
          locked: true,
        ),
        _menuBtn(
          'assets/icons/buttons/fight_btn.png',
          '攻防戰',
          onTap: null,
          locked: true,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(color: Colors.white12, height: 1),
        ),
        _menuBtn(null, '登出', icon: Icons.logout_rounded, onTap: _logout),
      ],
    );
  }

  Widget _menuBtn(
    String? assetPath,
    String label, {
    IconData? icon,
    required VoidCallback? onTap,
    bool locked = false,
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Opacity(
        opacity: locked ? 0.35 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: _btnIconSize,
                height: _btnIconSize,
                child: assetPath != null
                    ? Image.asset(assetPath, fit: BoxFit.contain)
                    : Icon(icon, color: Colors.white70, size: 28),
              ),
              const SizedBox(width: 10),
              // 展開動畫過程中面板暫時較窄，用 Expanded + 單行省略吸收，
              // 避免 Row 在窄寬度的影格觸發 overflow。
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: locked ? Colors.white38 : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Name watermark ────────────────────────────────────────────────────────

  Widget _buildNameWatermark() {
    return Text(
      _heritage.name.split('').join('  '),
      style: const TextStyle(
        color: Color(0xCCD4A843),
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: 5,
        shadows: [
          Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(1, 2)),
        ],
      ),
    );
  }

  // ── Intro animation ───────────────────────────────────────────────────────

  Widget _buildIntroOverlay(AppState state) {
    final t = _introCtrl.value;
    // 橫幅淡入(0-0.08) → 名稱(0.12) → 副標(0.35) → 整條淡出(0.70-1.0)
    final bandAlpha = _seg(0.00, 0.08, t) * (1.0 - _seg(0.70, 1.00, t));
    final nameIn = _seg(0.12, 0.30, t);
    final nameSlide = (1.0 - _seg(0.12, 0.35, t)) * 28.0;
    final subtitleIn = _seg(0.35, 0.50, t);
    final groupName = state.currentGroup?.name ?? '';

    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: bandAlpha.clamp(0.0, 1.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 46),
            decoration: const BoxDecoration(
              // 橫幅黑條，左右淡出
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0x00000000),
                  Color(0xD9000000),
                  Color(0xD9000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.16, 0.84, 1.0],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: nameIn.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, nameSlide),
                    child: Text(
                      _heritage.name.split('').join('   '),
                      style: const TextStyle(
                        color: Color(0xFFD4A843),
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 24,
                            offset: Offset(2, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (groupName.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: subtitleIn.clamp(0.0, 1.0),
                    child: Text(
                      groupName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _seg(double from, double to, double t) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);
}

/// 背包卡片（卡框圖磚 + 名稱）。用於編輯模式底部背包列。
class _InventoryCard extends StatelessWidget {
  final ComponentModel component;
  final int quantity;
  const _InventoryCard({required this.component, required this.quantity});

  @override
  Widget build(BuildContext context) {
    // Column 填滿背包列高度；圖磚用 Expanded 自適應，避免高度不足時 overflow。
    return SizedBox(
      width: 150,
      child: Column(
        children: [
          Expanded(
            child: FramedComponentTile(
              component: component,
              quantity: quantity,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            component.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
