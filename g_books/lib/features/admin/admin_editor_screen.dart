import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/component_data.dart';
import '../../data/models/heritage_config.dart';
import '../../data/models/heritage_slot.dart';
import '../../services/heritage_config_service.dart';
import '../fight/fight_map_geometry.dart';
import '../heritage/heritage_view_geometry.dart';

/// 管理者古蹟設定編輯器（取代舊 SlotEditorScreen）。四種模式：
///   - Slot：擺放 / 縮放 slot（八方向控制點），輸出 slot 幾何
///   - 原料對應：選一個原料，點 slot 切換可放與否
///   - 物品：自動列出該古蹟 assets 內的原料圖片，設定名稱與等級
///   - 世界地圖：在 fight_map.png 上擺放 / 縮放各組島格（攻防戰世界地圖用），作法同 Slot
///
/// 進場向（假）後端 [HeritageConfigService.fetch] 取設定；按「儲存」整包 [save] 回後端，
/// 並即時 [applyHeritageConfig] 讓執行中的 app 反映。
class AdminEditorScreen extends StatefulWidget {
  final String heritageId;
  const AdminEditorScreen({super.key, required this.heritageId});

  @override
  State<AdminEditorScreen> createState() => _AdminEditorScreenState();
}

enum _Mode { slots, mapping, items, mapCells }

enum _Grab { none, move, resize }

// 八方向控制點：(ax, ay) ∈ {-1,0,1}，(0,0) 不用。
const List<List<int>> _handleDirs = [
  [-1, -1], [0, -1], [1, -1],
  [-1, 0], [1, 0],
  [-1, 1], [0, 1], [1, 1],
];

class _AdminEditorScreenState extends State<AdminEditorScreen> {
  late final HeritageConfigService _service;

  bool _loading = true;
  bool _saving = false;
  _Mode _mode = _Mode.slots;

  // 編輯中狀態
  List<HeritageSlot> _slots = [];
  List<HeritageSlot> _cells = []; // 世界地圖島格（fight_map.png 正規化）
  Map<int, Set<int>> _allowed = {}; // componentId → 可放 slotIds
  final Map<int, ComponentMeta> _meta = {}; // componentId → 名稱/等級
  final Map<int, TextEditingController> _nameCtrls = {};
  late List<int> _imageIds; // 該古蹟可用原料圖片 id

  int? _selectedId; // slots 模式選取
  int? _mapComponentId; // mapping 模式選取的原料

  // 畫布變換：v = offset + scale * scenePoint
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  _Grab _grab = _Grab.none;
  HeritageSlot? _grabStart;
  int _hx = 0, _hy = 0;
  bool _moved = false;

  int _activePointers = 0;
  int _gestureMaxPointers = 0;
  DateTime _downTime = DateTime.now();
  static const int _tapMaxMs = 250;

  static const double _defaultSize = 0.06;
  static const double _minSize = 0.015;
  static const double _handleMaxPx = 11;

  @override
  void initState() {
    super.initState();
    _service = context.read<HeritageConfigService>();
    _imageIds = componentImageIdsOf(widget.heritageId);
    _load();
  }

  Future<void> _load() async {
    final cfg = await _service.fetch(widget.heritageId);
    if (!mounted) return;
    _applyLoaded(cfg);
    setState(() => _loading = false);
  }

  void _applyLoaded(HeritageConfig cfg) {
    _slots = cfg.slots.map((s) => s.copyWith()).toList();
    _cells = cfg.mapCells.map((s) => s.copyWith()).toList();
    _allowed = {
      for (final e in cfg.componentSlots.entries) e.key: Set<int>.from(e.value),
    };
    _meta.clear();
    for (final id in _imageIds) {
      _meta[id] = cfg.components[id]?.copy() ?? ComponentMeta(name: '', level: 1);
      final ctrl = _nameCtrls.putIfAbsent(id, () => TextEditingController());
      ctrl.text = _meta[id]!.name;
    }
    _mapComponentId = _imageIds.isNotEmpty ? _imageIds.first : null;
    _selectedId = null;
  }

  @override
  void dispose() {
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── slot helpers ────────────────────────────────────────────────────────────
  // 世界地圖模式編輯 _cells；其餘（slots / mapping）編輯 _slots。slot 與島格幾何相同
  // （cx/cy/w/h），擺放 / 縮放 / 選取邏輯共用，只差編輯哪份清單與底圖。
  bool get _cellMode => _mode == _Mode.mapCells;
  List<HeritageSlot> get _geom => _cellMode ? _cells : _slots;

  int get _nextId {
    final used = _geom.map((s) => s.id).toSet();
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    return id;
  }

  HeritageSlot? get _selected {
    for (final s in _geom) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  void _replace(HeritageSlot updated) {
    final i = _geom.indexWhere((s) => s.id == updated.id);
    if (i >= 0) _geom[i] = updated;
  }

  /// 底圖（main.png 或 fight_map.png）的置中顯示矩形。slots / mapping 用正方形
  /// （main.png 為正方）；世界地圖用 fight_map.png 的原圖長寬比，slot / 島格座標皆
  /// 正規化於此矩形。
  Rect _baseRect(Size viewport) {
    final center = Offset(viewport.width / 2, viewport.height / 2);
    if (_cellMode) {
      final maxSide = viewport.shortestSide * 0.92;
      var w = maxSide;
      var h = w / FightMapGeometry.mainAspect;
      if (h > maxSide) {
        h = maxSide;
        w = h * FightMapGeometry.mainAspect;
      }
      return Rect.fromCenter(center: center, width: w, height: h);
    }
    final side = viewport.shortestSide * 0.92;
    return Rect.fromCenter(center: center, width: side, height: side);
  }

  Offset _toScene(Offset viewportPt) => (viewportPt - _offset) / _scale;

  double _handleSceneR(Rect rect) {
    final minScreen = math.min(rect.width, rect.height) * _scale;
    final px = (minScreen * 0.28).clamp(3.0, _handleMaxPx);
    return px / _scale;
  }

  Offset _handlePos(Rect r, int ax, int ay) => Offset(
        ax < 0 ? r.left : (ax > 0 ? r.right : r.center.dx),
        ay < 0 ? r.top : (ay > 0 ? r.bottom : r.center.dy),
      );

  String _componentImage(int id) =>
      'assets/heritages/${widget.heritageId}/components/$id.png';

  String _displayName(int id) {
    final t = _nameCtrls[id]?.text.trim() ?? '';
    return t.isNotEmpty ? t : '原料$id';
  }

  // ── gesture ─────────────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d, Rect main) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
    _moved = false;
    _grab = _Grab.none;
    _grabStart = null;

    if (_mode != _Mode.slots && _mode != _Mode.mapCells) return;

    final scene = _toScene(d.localFocalPoint);
    final sel = _selected;
    if (sel != null) {
      final r = HeritageViewGeometry.slotRect(sel, main);
      final hitR = _handleSceneR(r) * 1.6;
      for (final dir in _handleDirs) {
        if ((scene - _handlePos(r, dir[0], dir[1])).distance <= hitR) {
          _grab = _Grab.resize;
          _grabStart = sel;
          _hx = dir[0];
          _hy = dir[1];
          return;
        }
      }
    }
    for (final s in _geom.reversed) {
      if (HeritageViewGeometry.slotRect(s, main).contains(scene)) {
        _grab = _Grab.move;
        _grabStart = s;
        return;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Rect main) {
    if (d.pointerCount >= 2) {
      _moved = true;
      final newScale = (_startScale * d.scale).clamp(0.5, 12.0);
      final sceneAtFocal = (_startFocal - _startOffset) / _startScale;
      setState(() {
        _scale = newScale;
        _offset = d.localFocalPoint - sceneAtFocal * newScale;
      });
      return;
    }

    final screenDelta = d.localFocalPoint - _startFocal;
    if (screenDelta.distance > 3) _moved = true;
    final sceneDelta = screenDelta / _scale;

    if (_grab == _Grab.move && _grabStart != null) {
      final g = _grabStart!;
      setState(() {
        _replace(g.copyWith(
          cx: (g.cx + sceneDelta.dx / main.width).clamp(0.0, 1.0),
          cy: (g.cy + sceneDelta.dy / main.height).clamp(0.0, 1.0),
        ));
        _selectedId = g.id;
      });
    } else if (_grab == _Grab.resize && _grabStart != null) {
      _applyResize(sceneDelta, main);
    } else {
      setState(() => _offset = _startOffset + screenDelta);
    }
  }

  void _applyResize(Offset sceneDelta, Rect main) {
    final start = HeritageViewGeometry.slotRect(_grabStart!, main);
    var left = start.left + (_hx < 0 ? sceneDelta.dx : 0);
    var right = start.right + (_hx > 0 ? sceneDelta.dx : 0);
    var top = start.top + (_hy < 0 ? sceneDelta.dy : 0);
    var bottom = start.bottom + (_hy > 0 ? sceneDelta.dy : 0);
    final minW = _minSize * main.width;
    final minH = _minSize * main.height;
    if (right - left < minW) {
      if (_hx < 0) {
        left = right - minW;
      } else {
        right = left + minW;
      }
    }
    if (bottom - top < minH) {
      if (_hy < 0) {
        top = bottom - minH;
      } else {
        bottom = top + minH;
      }
    }
    setState(() {
      _replace(_grabStart!.copyWith(
        cx: (((left + right) / 2 - main.left) / main.width).clamp(0.0, 1.0),
        cy: (((top + bottom) / 2 - main.top) / main.height).clamp(0.0, 1.0),
        w: ((right - left) / main.width).clamp(_minSize, 1.0),
        h: ((bottom - top) / main.height).clamp(_minSize, 1.0),
      ));
      _selectedId = _grabStart!.id;
    });
  }

  void _onScaleEnd(Rect main) {
    final elapsed = DateTime.now().difference(_downTime).inMilliseconds;
    final wasTap = !_moved && _gestureMaxPointers <= 1 && elapsed <= _tapMaxMs;
    if (wasTap) {
      final scene = _toScene(_startFocal);
      if (_mode == _Mode.slots || _mode == _Mode.mapCells) {
        if (_grab != _Grab.none && _grabStart != null) {
          setState(() => _selectedId = _grabStart!.id);
        } else if (_selectedId != null) {
          setState(() => _selectedId = null);
        } else {
          _addAtScene(scene, main);
        }
      } else if (_mode == _Mode.mapping) {
        _toggleMappingAt(scene, main);
      }
    }
    _grab = _Grab.none;
    _grabStart = null;
  }

  void _addAtScene(Offset scene, Rect main) {
    final cx = ((scene.dx - main.left) / main.width).clamp(0.0, 1.0);
    final cy = ((scene.dy - main.top) / main.height).clamp(0.0, 1.0);
    // 島格預設比 slot 大（要塞得下一座島嶼）。
    final size = _cellMode ? 0.2 : _defaultSize;
    final slot = HeritageSlot(id: _nextId, cx: cx, cy: cy, w: size, h: size);
    setState(() {
      _geom.add(slot);
      _selectedId = slot.id;
    });
  }

  void _toggleMappingAt(Offset scene, Rect main) {
    final cid = _mapComponentId;
    if (cid == null) return;
    for (final s in _slots.reversed) {
      if (HeritageViewGeometry.slotRect(s, main).contains(scene)) {
        setState(() {
          final set = _allowed.putIfAbsent(cid, () => <int>{});
          if (!set.add(s.id)) set.remove(s.id);
        });
        return;
      }
    }
  }

  // ── actions ───────────────────────────────────────────────────────────────
  void _deleteSelected() {
    if (_selectedId == null) return;
    setState(() {
      _geom.removeWhere((s) => s.id == _selectedId);
      _selectedId = null;
    });
  }

  void _resetView() => setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
      });

  void _zoom(double factor, Size viewport) {
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final newScale = (_scale * factor).clamp(0.5, 12.0);
    final sceneAtCenter = (center - _offset) / _scale;
    setState(() {
      _scale = newScale;
      _offset = center - sceneAtCenter * newScale;
    });
  }

  Future<void> _reloadFromServer() async {
    setState(() => _loading = true);
    final cfg = await _service.fetch(widget.heritageId);
    if (!mounted) return;
    _applyLoaded(cfg);
    setState(() => _loading = false);
  }

  HeritageConfig _buildConfig() {
    _slots.sort((a, b) => a.id.compareTo(b.id));
    _cells.sort((a, b) => a.id.compareTo(b.id));
    final componentSlots = <int, Set<int>>{
      for (final e in _allowed.entries)
        if (e.value.isNotEmpty) e.key: Set<int>.from(e.value),
    };
    final components = <int, ComponentMeta>{
      for (final id in _imageIds)
        id: ComponentMeta(
          name: _nameCtrls[id]?.text.trim() ?? '',
          level: _meta[id]?.level ?? 1,
        ),
    };
    return HeritageConfig(
      slots: _slots,
      componentSlots: componentSlots,
      components: components,
      mapCells: _cells,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final cfg = _buildConfig();
    await _service.save(widget.heritageId, cfg);
    // 即時套用，讓執行中的學生畫面與此處下次進入都反映新值。
    applyHeritageConfig(widget.heritageId, cfg);
    if (!mounted) return;
    setState(() => _saving = false);
    Fluttertoast.showToast(msg: '已儲存並同步');
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD4A843)))
            : LayoutBuilder(
                builder: (_, constraints) {
                  final viewport =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final main = _baseRect(viewport);
                  return Stack(
                    children: [
                      if (_mode != _Mode.items) ...[
                        _buildCanvas(viewport, main),
                        _buildBottomOverlay(),
                        _buildZoomControls(viewport),
                      ] else
                        _buildItemsEditor(),
                      _buildTopOverlay(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  // ── items（物品）模式 ─────────────────────────────────────────────────────────
  Widget _buildItemsEditor() {
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 64, 12, 12),
        child: _imageIds.isEmpty
            ? const Center(
                child: Text('此古蹟尚無原料圖片\n（放入 components/<id>.png 後即可編輯）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 15)),
              )
            : ListView.separated(
                itemCount: _imageIds.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _itemRow(_imageIds[i]),
              ),
      ),
    );
  }

  Widget _itemRow(int id) {
    final level = _meta[id]?.level ?? 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2225),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Image.asset(_componentImage(id),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                    Icons.image_not_supported, color: Colors.white24)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Text('#$id',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: TextField(
              controller: _nameCtrls[id],
              onChanged: (v) => _meta[id]?.name = v,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: '原料名稱',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF15171A),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          for (final lv in const [1, 2, 3]) _levelChip(id, lv, level == lv),
        ],
      ),
    );
  }

  Widget _levelChip(int id, int lv, bool on) {
    const colors = {
      1: Color(0xFF6FBF73),
      2: Color(0xFFE3B341),
      3: Color(0xFFD9534F),
    };
    final c = colors[lv]!;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => setState(() => _meta[id]?.level = lv),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.30) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: on ? c : Colors.white24, width: on ? 2 : 1),
          ),
          child: Text('$lv',
              style: TextStyle(
                  color: on ? c : Colors.white38,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      ),
    );
  }

  // ── 畫布（slots / mapping 共用）───────────────────────────────────────────────
  Widget _buildCanvas(Size viewport, Rect main) {
    return Positioned.fill(
      child: Listener(
        onPointerDown: (_) {
          if (_activePointers == 0) {
            _gestureMaxPointers = 0;
            _downTime = DateTime.now();
          }
          _activePointers++;
          _gestureMaxPointers = math.max(_gestureMaxPointers, _activePointers);
        },
        onPointerUp: (_) => _activePointers = math.max(0, _activePointers - 1),
        onPointerCancel: (_) =>
            _activePointers = math.max(0, _activePointers - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) => _onScaleStart(d, main),
          onScaleUpdate: (d) => _onScaleUpdate(d, main),
          onScaleEnd: (_) => _onScaleEnd(main),
          child: ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                ..scaleByDouble(_scale, _scale, 1, 1),
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: main,
                            child: Image.asset(
                              _cellMode
                                  ? 'assets/images/fight_map.png'
                                  : 'assets/heritages/${widget.heritageId}/main.png',
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.low,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.white10,
                                alignment: Alignment.center,
                                child: Text(
                                    _cellMode
                                        ? 'fight_map.png 不存在'
                                        : 'main.png 不存在',
                                    style: const TextStyle(
                                        color: Colors.white38)),
                              ),
                            ),
                          ),
                          Positioned.fromRect(
                            rect: main,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final s in _geom) _slotBox(s, main),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slotBox(HeritageSlot s, Rect main) {
    final rect = HeritageViewGeometry.slotRect(s, main);
    final mapping = _mode == _Mode.mapping;
    final allowedForComp =
        mapping && (_allowed[_mapComponentId]?.contains(s.id) ?? false);
    final selected = !mapping && s.id == _selectedId;

    final Color color;
    final double fill;
    final double borderW;
    if (mapping) {
      color = allowedForComp ? const Color(0xFF00E676) : const Color(0xFFFF3B30);
      fill = allowedForComp ? 0.50 : 0.22;
      borderW = allowedForComp ? 3 : 1.5;
    } else {
      color = selected ? const Color(0xFFD4A843) : Colors.cyanAccent;
      fill = 0.18;
      borderW = selected ? 2 : 1;
    }
    final r = _handleSceneR(rect);

    return Positioned.fromRect(
      rect: rect.inflate(r * 1.5),
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: r * 1.5,
              top: r * 1.5,
              width: rect.width,
              height: rect.height,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: fill),
                  border: Border.all(color: color, width: borderW),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${s.id}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
            ),
            if (selected)
              for (final dir in _handleDirs)
                Positioned(
                  left: r * 1.5 +
                      (dir[0] < 0
                          ? 0
                          : (dir[0] > 0 ? rect.width : rect.width / 2)) -
                      r,
                  top: r * 1.5 +
                      (dir[1] < 0
                          ? 0
                          : (dir[1] > 0 ? rect.height : rect.height / 2)) -
                      r,
                  width: r * 2,
                  height: r * 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A843),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black54, width: 0.5),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ── overlays ────────────────────────────────────────────────────────────────
  Widget _buildTopOverlay() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          _pill(
            child: InkWell(
              onTap: () => context.pop(),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          _pill(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _modeTab('Slot', _Mode.slots),
              const SizedBox(width: 4),
              _modeTab('原料對應', _Mode.mapping),
              const SizedBox(width: 4),
              _modeTab('物品', _Mode.items),
              const SizedBox(width: 4),
              _modeTab('世界地圖', _Mode.mapCells),
            ]),
          ),
          const Spacer(),
          if (_mode != _Mode.items)
            _pill(
              child: InkWell(
                onTap: _reloadFromServer,
                child: const Icon(Icons.restore, color: Colors.white, size: 20),
              ),
            ),
          const SizedBox(width: 8),
          _pill(
            child: InkWell(
              onTap: _saving ? null : _save,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFD4A843)),
                  )
                else
                  const Icon(Icons.save_outlined,
                      color: Color(0xFFD4A843), size: 18),
                const SizedBox(width: 6),
                Text(_saving ? '儲存中' : '儲存',
                    style:
                        const TextStyle(color: Color(0xFFD4A843), fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _Mode m) {
    final on = _mode == m;
    return GestureDetector(
      // 切換模式時清掉選取（slots 與島格的 id 各自獨立）。
      onTap: () => setState(() {
        _mode = m;
        _selectedId = null;
        _grab = _Grab.none;
        _grabStart = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFD4A843) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? Colors.black87 : Colors.white70,
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    if (_mode == _Mode.mapping) return _buildComponentPicker();
    final sel = _selected;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Row(
        children: [
          Flexible(
            child: _pill(
              child: sel == null
                  ? const Text('點空白新增 · 拖曳移動 · 八方控制點縮放 · 兩指縮放畫布',
                      style: TextStyle(color: Colors.white54, fontSize: 12))
                  : Text(
                      '#${sel.id}  x:${sel.cx.toStringAsFixed(3)} '
                      'y:${sel.cy.toStringAsFixed(3)} '
                      'w:${sel.w.toStringAsFixed(3)} h:${sel.h.toStringAsFixed(3)}',
                      style: const TextStyle(
                          color: Color(0xFFD4A843), fontSize: 12),
                    ),
            ),
          ),
          if (sel != null) ...[
            const SizedBox(width: 8),
            _pill(
              child: InkWell(
                onTap: _deleteSelected,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  SizedBox(width: 4),
                  Text('刪除',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComponentPicker() {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: _pill(
        child: SizedBox(
          height: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('選原料後，點 main 上的 slot 切換可放（綠色=可放）',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageIds.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final id = _imageIds[i];
                    final on = id == _mapComponentId;
                    final count = _allowed[id]?.length ?? 0;
                    return GestureDetector(
                      onTap: () => setState(() => _mapComponentId = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: on ? const Color(0xFFD4A843) : Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Image.asset(_componentImage(id),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const SizedBox()),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_displayName(id),
                                    style: TextStyle(
                                        color:
                                            on ? Colors.black87 : Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                Text('$count slot',
                                    style: TextStyle(
                                        color: on
                                            ? Colors.black54
                                            : Colors.white38,
                                        fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls(Size viewport) {
    return Positioned(
      right: 8,
      bottom: 96,
      child: Column(
        children: [
          _zoomBtn(Icons.add, () => _zoom(1.25, viewport)),
          const SizedBox(height: 8),
          _zoomBtn(Icons.remove, () => _zoom(0.8, viewport)),
          const SizedBox(height: 8),
          _zoomBtn(Icons.center_focus_strong, _resetView),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
              color: Color(0xCC1F2225), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _pill({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xCC1F2225),
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      );
}
