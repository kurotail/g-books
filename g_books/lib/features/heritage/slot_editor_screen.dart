import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../data/component_data.dart';
import '../../data/models/heritage_slot.dart';
import '../../data/slot_data.dart';
import 'heritage_view_geometry.dart';

/// 開發用編輯器，兩種模式：
///   - Slot 模式：擺放 / 縮放 slot（八方向控制點），輸出 slot 幾何 JSON
///   - 原料對應模式：選一個原料，點 slot 切換可放與否，輸出原料→slot 對應 JSON
///
/// 手勢：兩指縮放/平移畫布；單指拖 slot 本體=移動；拖控制點=縮放；拖空白=平移；
/// 點空白=新增 slot（Slot 模式）。座標為 main.png 正規化值（與顯示縮放無關）。
class SlotEditorScreen extends StatefulWidget {
  final String heritageId;
  const SlotEditorScreen({super.key, required this.heritageId});

  @override
  State<SlotEditorScreen> createState() => _SlotEditorScreenState();
}

enum _Mode { slots, mapping }

enum _Grab { none, move, resize }

// 八方向控制點：(ax, ay) ∈ {-1,0,1}，(0,0) 不用。
const List<List<int>> _handleDirs = [
  [-1, -1], [0, -1], [1, -1],
  [-1, 0], [1, 0],
  [-1, 1], [0, 1], [1, 1],
];

class _SlotEditorScreenState extends State<SlotEditorScreen> {
  _Mode _mode = _Mode.slots;

  late List<HeritageSlot> _slots;
  int? _selectedId;

  // 原料對應：componentId → 可放 slotIds
  late Map<int, Set<int>> _allowed;
  int? _mapComponentId;

  // 畫布變換：v = offset + scale * scenePoint
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // 手勢暫存
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  _Grab _grab = _Grab.none;
  HeritageSlot? _grabStart;
  int _hx = 0, _hy = 0; // resize 方向
  bool _moved = false;

  // 以 Listener 自行統計觸點，避免雙指誤判為點擊；並用按住時間判定 click。
  int _activePointers = 0;
  int _gestureMaxPointers = 0;
  DateTime _downTime = DateTime.now();
  static const int _tapMaxMs = 250; // 按下→放開 < 0.25s 才算點擊

  static const double _defaultSize = 0.06;
  static const double _minSize = 0.015;
  static const double _handleMaxPx = 11; // 控制點螢幕半徑上限

  @override
  void initState() {
    super.initState();
    _slots = slotsOf(widget.heritageId).map((s) => s.copyWith()).toList();
    _allowed = {
      for (final c in componentsOf(widget.heritageId))
        c.id: Set<int>.from(c.allowedSlotIds),
    };
    final comps = componentsOf(widget.heritageId);
    if (comps.isNotEmpty) _mapComponentId = comps.first.id;
  }

  // ── slot helpers ────────────────────────────────────────────────────────────

  int get _nextId {
    final used = _slots.map((s) => s.id).toSet();
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    return id;
  }

  HeritageSlot? get _selected {
    for (final s in _slots) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  void _replace(HeritageSlot updated) {
    final i = _slots.indexWhere((s) => s.id == updated.id);
    if (i >= 0) _slots[i] = updated;
  }

  Offset _toScene(Offset viewportPt) => (viewportPt - _offset) / _scale;

  /// 控制點 scene 半徑：上限 [_handleMaxPx] 螢幕像素，但當 slot 在螢幕上變小時，
  /// 隨之縮小（取 slot 較短邊螢幕長度的 0.28），避免小 slot 被控制點蓋住。
  double _handleSceneR(Rect rect) {
    final minScreen = math.min(rect.width, rect.height) * _scale;
    final px = (minScreen * 0.28).clamp(3.0, _handleMaxPx);
    return px / _scale;
  }

  Offset _handlePos(Rect r, int ax, int ay) => Offset(
        ax < 0 ? r.left : (ax > 0 ? r.right : r.center.dx),
        ay < 0 ? r.top : (ay > 0 ? r.bottom : r.center.dy),
      );

  // ── gesture ─────────────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d, Rect main) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
    _moved = false;
    _grab = _Grab.none;
    _grabStart = null;

    if (_mode != _Mode.slots) return; // 對應模式只看點擊（在 end 處理）

    final scene = _toScene(d.localFocalPoint);

    // 1) 選取中 slot 的八方向控制點 → 縮放
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
    // 2) slot 本體 → 移動
    for (final s in _slots.reversed) {
      if (HeritageViewGeometry.slotRect(s, main).contains(scene)) {
        _grab = _Grab.move;
        _grabStart = s;
        return;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Rect main) {
    // 兩指：縮放 + 平移畫布
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
    // 避免翻轉
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
    // 點擊判定：全程單指 + 幾乎沒移動 + 按住時間夠短。
    final wasTap = !_moved && _gestureMaxPointers <= 1 && elapsed <= _tapMaxMs;
    if (wasTap) {
      final scene = _toScene(_startFocal);
      if (_mode == _Mode.slots) {
        if (_grab != _Grab.none && _grabStart != null) {
          setState(() => _selectedId = _grabStart!.id);
        } else if (_selectedId != null) {
          // 空白點擊：先取消先前選取（不新增）
          setState(() => _selectedId = null);
        } else {
          // 沒有選取才新增 slot
          _addAtScene(scene, main);
        }
      } else {
        _toggleMappingAt(scene, main);
      }
    }
    _grab = _Grab.none;
    _grabStart = null;
  }

  void _addAtScene(Offset scene, Rect main) {
    final cx = ((scene.dx - main.left) / main.width).clamp(0.0, 1.0);
    final cy = ((scene.dy - main.top) / main.height).clamp(0.0, 1.0);
    final slot =
        HeritageSlot(id: _nextId, cx: cx, cy: cy, w: _defaultSize, h: _defaultSize);
    setState(() {
      _slots.add(slot);
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
      _slots.removeWhere((s) => s.id == _selectedId);
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

  void _resetToSaved() => setState(() {
        _slots = slotsOf(widget.heritageId).map((s) => s.copyWith()).toList();
        _allowed = {
          for (final c in componentsOf(widget.heritageId))
            c.id: Set<int>.from(c.allowedSlotIds),
        };
        _selectedId = null;
      });

  void _export() {
    final String jsonStr;
    final String path;
    if (_mode == _Mode.slots) {
      _slots.sort((a, b) => a.id.compareTo(b.id));
      jsonStr = const JsonEncoder.withIndent('  ')
          .convert(_slots.map((s) => s.toJson()).toList());
      path = 'assets/data/slots/${widget.heritageId}.json';
    } else {
      final map = <String, List<int>>{};
      final ids = _allowed.keys.toList()..sort();
      for (final id in ids) {
        map['$id'] = _allowed[id]!.toList()..sort();
      }
      jsonStr = const JsonEncoder.withIndent('  ').convert(map);
      path = 'assets/data/component_slots/${widget.heritageId}.json';
    }
    Clipboard.setData(ClipboardData(text: jsonStr));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1F2225),
        title: const Text('JSON（已複製到剪貼簿）',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              '貼到 $path 後 hot restart 即生效。\n\n$jsonStr',
              style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉')),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            final side = viewport.shortestSide * 0.92;
            final main = Rect.fromCenter(
              center: Offset(viewport.width / 2, viewport.height / 2),
              width: side,
              height: side,
            );
            return Stack(
              children: [
                _buildCanvas(viewport, main),
                _buildTopOverlay(),
                _buildBottomOverlay(),
                _buildZoomControls(viewport),
              ],
            );
          },
        ),
      ),
    );
  }

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
        onPointerUp: (_) =>
            _activePointers = math.max(0, _activePointers - 1),
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
                            'assets/images/heritages/${widget.heritageId}/main.png',
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.white10,
                              alignment: Alignment.center,
                              child: const Text('main.png 不存在',
                                  style: TextStyle(color: Colors.white38)),
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
                  for (final s in _slots) _slotBox(s, main),
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
      // 已選(可放)=亮綠色，未選=紅色
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
            // 八方向控制點（固定螢幕大小：scene 半徑 = px / scale）
            if (selected)
              for (final dir in _handleDirs)
                Positioned(
                  left: r * 1.5 +
                      (dir[0] < 0 ? 0 : (dir[0] > 0 ? rect.width : rect.width / 2)) -
                      r,
                  top: r * 1.5 +
                      (dir[1] < 0 ? 0 : (dir[1] > 0 ? rect.height : rect.height / 2)) -
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
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // 模式切換
          _pill(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _modeTab('Slot', _Mode.slots),
              const SizedBox(width: 4),
              _modeTab('原料對應', _Mode.mapping),
            ]),
          ),
          const Spacer(),
          if (_mode == _Mode.slots)
            _pill(
              child: InkWell(
                onTap: _resetToSaved,
                child: const Icon(Icons.restore, color: Colors.white, size: 20),
              ),
            ),
          const SizedBox(width: 8),
          _pill(
            child: InkWell(
              onTap: _export,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.code, color: Color(0xFFD4A843), size: 18),
                SizedBox(width: 6),
                Text('輸出 JSON',
                    style: TextStyle(color: Color(0xFFD4A843), fontSize: 13)),
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
      onTap: () => setState(() => _mode = m),
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
                  Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 18),
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
    final comps = componentsOf(widget.heritageId);
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
              const Text('選原料後，點 main 上的 slot 切換可放（金色=可放）',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: comps.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = comps[i];
                    final on = c.id == _mapComponentId;
                    final count = _allowed[c.id]?.length ?? 0;
                    return GestureDetector(
                      onTap: () => setState(() => _mapComponentId = c.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: on
                              ? const Color(0xFFD4A843)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Image.asset(c.imagePath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const SizedBox()),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    style: TextStyle(
                                        color: on
                                            ? Colors.black87
                                            : Colors.white,
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
