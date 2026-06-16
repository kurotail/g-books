import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import '../../services/game_state_service.dart';
import '../../services/teacher_service.dart';
import '../../state/app_state.dart';

/// 教師控制台：遊戲階段（含時長 / 時間到自動回平時）/ 學生帳號 / 小組設定 /
/// 上課古蹟 / 題目匯入。操作走 [TeacherService]，目前階段讀 [GameStateService]。
///
/// 「開始上課」後會鎖定結構性設定（學生分組、新增帳號），避免上課中誤改。
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  static const _bg = Color(0xFF15171A);
  static const _panel = Color(0xFF1E2125);
  static const _field = Color(0xFF14161A);
  static const _gold = Color(0xFFD4A843);

  late final TeacherService _teacher;
  late final GameStateService _gameSvc;

  int _tab = 0;
  // 兩階段：課前準備（學生 / 分組 / 上課古蹟）→ 開始課程 → 課程控制（遊戲階段）。
  // 課程進行中即視為鎖定結構設定（_locked），且只會停在課程控制頁，回不到準備頁。
  bool _courseStarted = false;
  bool get _locked => _courseStarted;

  // 階段 + 時長 / 倒數
  GamePhase? _phase;
  bool _busyPhase = false;
  int _durationMin = 5; // 採集 / 攻防的時長（分）
  DateTime? _phaseEndsAt; // 本機倒數結束時間
  Timer? _autoTimer; // 時間到自動回平時
  Timer? _ticker; // 每秒刷新倒數顯示

  // 學生
  List<TeacherStudent> _students = const [];
  bool _loadingStudents = false;

  // 小組設定
  int _detailGroup = 1; // 第一區塊目前檢視的組別
  final Set<int> _extraGroups = {}; // 手動新增、暫無成員的空組
  final Map<int, String> _groupNames = {}; // 本機記住的組名（後端無「列出所有組」端點）

  String _selectedHeritage = 'beigang_chaotian_temple';
  bool _applyingHeritage = false;
  bool _resetting = false;

  final _nameCtrl = TextEditingController();
  final _seatCtrl = TextEditingController();
  final _csvCtrl = TextEditingController();
  final _groupNameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _teacher = context.read<TeacherService>();
    _gameSvc = context.read<GameStateService>();
    _refreshPhase();
    _refreshStudents();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ticker?.cancel();
    _nameCtrl.dispose();
    _seatCtrl.dispose();
    _csvCtrl.dispose();
    _groupNameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 階段 ────────────────────────────────────────────────────────────────────
  Future<void> _refreshPhase() async {
    try {
      final s = await _gameSvc.fetch();
      if (mounted) setState(() => _phase = s.phase);
    } catch (_) {}
  }

  /// 平時：立即停止。採集 / 攻防：先由 [_onSelectPhase] 設定時長，再帶 [dur] 進來。
  Future<void> _startPhase(GamePhase p, {Duration? dur}) async {
    if (_busyPhase) return;
    setState(() => _busyPhase = true);
    try {
      if (p == GamePhase.normal) {
        await _teacher.setPhase(GamePhase.normal);
        _clearTimers();
        _toast('已回到平時');
      } else {
        final d = dur ?? Duration(minutes: _durationMin);
        await _teacher.setPhase(p, duration: d);
        _startTimers(d);
        _toast('已開始「${_phaseName(p)}」（${d.inMinutes} 分）');
      }
      await _refreshPhase();
    } catch (e) {
      _toast('切換失敗：${_msg(e)}');
    } finally {
      if (mounted) setState(() => _busyPhase = false);
    }
  }

  /// 點選階段：平時直接停止；採集 / 攻防先跳對話框設時長，確定才開始。
  Future<void> _onSelectPhase(GamePhase p) async {
    if (_busyPhase) return;
    if (p == GamePhase.normal) {
      await _startPhase(GamePhase.normal);
      return;
    }
    final dur = await _askDuration(p);
    if (dur == null) return; // 取消
    await _startPhase(p, dur: dur);
  }

  /// 設定時長對話框。回傳所選時長，或 null（取消）。
  Future<Duration?> _askDuration(GamePhase p) {
    int min = _durationMin;
    return showDialog<Duration>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(p == GamePhase.quiz1 ? Icons.spa_rounded : Icons.shield_rounded,
                  color: _gold),
              const SizedBox(width: 10),
              Text('開始「${_phaseName(p)}」',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('設定本階段時長，時間到會自動結算並回到平時。',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in const [3, 5, 10, 15])
                    _dlgChip(m, min == m, () => setLocal(() => min = m)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('自訂', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(width: 14),
                  _stepBtn(Icons.remove_rounded,
                      () => setLocal(() => min = (min - 1).clamp(1, 60))),
                  Container(
                    width: 64,
                    alignment: Alignment.center,
                    child: Text('$min 分',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  _stepBtn(Icons.add_rounded,
                      () => setLocal(() => min = (min + 1).clamp(1, 60))),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                _durationMin = min;
                Navigator.pop(ctx, Duration(minutes: min));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF2A1A0A),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: const Text('開始',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dlgChip(int min, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: on ? _gold : _field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? _gold : Colors.white24),
        ),
        child: Text('$min 分',
            style: TextStyle(
                color: on ? const Color(0xFF2A1A0A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  void _startTimers(Duration dur) {
    _clearTimers();
    _phaseEndsAt = DateTime.now().add(dur);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final e = _phaseEndsAt;
      if (e != null && !DateTime.now().isBefore(e)) _autoEnd();
    });
    _autoTimer = Timer(dur, _autoEnd);
  }

  void _clearTimers() {
    _autoTimer?.cancel();
    _ticker?.cancel();
    _autoTimer = null;
    _ticker = null;
    _phaseEndsAt = null;
  }

  /// 時間到：結算並自動回平時。（目前結算 = 結束該階段 + 回平時；詳細計分待後端定義。）
  Future<void> _autoEnd() async {
    if (_phaseEndsAt == null) return;
    _clearTimers();
    try {
      await _teacher.setPhase(GamePhase.normal);
    } catch (_) {}
    await _refreshPhase();
    if (mounted) _toast('時間到，已結算並回到平時');
  }

  Duration get _remaining {
    final e = _phaseEndsAt;
    if (e == null) return Duration.zero;
    final r = e.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  // ── 學生 / 小組 ───────────────────────────────────────────────────────────────
  Future<void> _refreshStudents() async {
    setState(() => _loadingStudents = true);
    try {
      final list = await _teacher.listStudents();
      if (mounted) setState(() => _students = list);
    } catch (e) {
      _toast('讀取學生名單失敗：${_msg(e)}');
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<void> _addStudent() async {
    if (_locked) return;
    final name = _nameCtrl.text.trim();
    final seat = _seatCtrl.text.trim();
    if (name.isEmpty || seat.isEmpty) {
      _toast('請輸入姓名與座號');
      return;
    }
    try {
      await _teacher.registerStudent(name: name, seat: seat);
      _nameCtrl.clear();
      _seatCtrl.clear();
      await _refreshStudents();
      _toast('已新增 ${name}_$seat');
    } catch (e) {
      _toast('新增失敗：${_msg(e)}');
    }
  }

  Future<void> _importCsv() async {
    if (_locked) return;
    final lines = _csvCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      _toast('請先貼上名單');
      return;
    }
    var created = 0, skipped = 0;
    for (final line in lines) {
      final parts = line.split(RegExp(r'[,\t]')).map((p) => p.trim()).toList();
      if (parts.length < 2) {
        skipped++;
        continue;
      }
      if (parts.any((p) => p.contains('座號') || p.contains('姓名'))) continue;
      final firstIsSeat = RegExp(r'^\d+$').hasMatch(parts[0]);
      final seat = firstIsSeat ? parts[0] : parts[1];
      final name = firstIsSeat ? parts[1] : parts[0];
      if (name.isEmpty || seat.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await _teacher.registerStudent(name: name, seat: seat);
        created++;
      } catch (_) {
        skipped++;
      }
    }
    _csvCtrl.clear();
    await _refreshStudents();
    _toast('匯入完成：新增 $created 筆，略過 $skipped 筆');
  }

  Future<void> _deleteStudent(TeacherStudent s) async {
    final ok =
        await _confirm('刪除學生', '確定刪除「${s.name}（座號 ${s.seat}）」的帳號？', '刪除');
    if (ok != true) return;
    try {
      await _teacher.deleteStudent(username: s.username);
      await _refreshStudents();
      _toast('已刪除 ${s.name}');
    } catch (e) {
      _toast('刪除失敗：${_msg(e)}');
    }
  }

  /// 重置進度：刪除全班所有學生帳號（前端逐一呼叫刪除；後端暫不另設 reset 端點）。
  /// 古蹟設定與題庫保留。之後若有「儲存古蹟進度」再加後端 reset。
  Future<void> _resetProgress() async {
    final n = _students.length;
    if (n == 0) {
      _toast('目前沒有學生帳號');
      return;
    }
    final ok = await _confirm(
        '重置進度', '將刪除全部 $n 位學生帳號（含分組）。古蹟設定與題庫會保留。確定重置？', '重置');
    if (ok != true) return;
    setState(() => _resetting = true);
    var done = 0;
    try {
      for (final s in List<TeacherStudent>.from(_students)) {
        try {
          await _teacher.deleteStudent(username: s.username);
          done++;
        } catch (_) {}
      }
      _extraGroups.clear();
      _groupNames.clear();
      _detailGroup = 1;
      await _refreshStudents();
      _toast('已重置：刪除 $done 位學生帳號');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _assignGroup(TeacherStudent s, int groupId) async {
    if (_locked) return;
    try {
      await _teacher.assignGroup(username: s.username, groupId: groupId);
      await _refreshStudents();
    } catch (e) {
      _toast('分組失敗：${_msg(e)}');
    }
  }

  Future<void> _renameGroup() async {
    final name = _groupNameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('請輸入小組名稱');
      return;
    }
    try {
      await _teacher.renameGroup(groupId: _detailGroup, name: name);
      setState(() => _groupNames[_detailGroup] = name);
      _toast('已將第 $_detailGroup 組命名為「$name」');
    } catch (e) {
      _toast('命名失敗：${_msg(e)}');
    }
  }

  List<int> get _groupIds {
    final s = <int>{
      for (final st in _students)
        if (st.groupId > 0) st.groupId,
      ..._extraGroups,
    };
    if (s.isEmpty) s.add(1);
    return s.toList()..sort();
  }

  int get _maxGroupOption {
    final ids = _groupIds;
    return ids.isEmpty ? 6 : (ids.last > 6 ? ids.last : 6);
  }

  void _selectDetailGroup(int id) {
    setState(() {
      _detailGroup = id;
      _groupNameCtrl.text = _groupNames[id] ?? '';
    });
  }

  void _addGroup() {
    if (_locked) return;
    final next = _groupIds.last + 1;
    setState(() => _extraGroups.add(next));
    _selectDetailGroup(next);
  }

  /// 進入課程控制（由「上課古蹟」套用後呼叫）。鎖定準備頁、切到遊戲階段。
  void _startCourse() {
    setState(() {
      _courseStarted = true;
      _tab = 0;
    });
    _toast('課程已開始，進入課程控制');
  }

  /// 結束課程：回平時、解鎖準備頁、回到「上課古蹟」分頁。
  Future<void> _endCourse() async {
    final ok = await _confirm('結束課程', '結束後會回到平時，並解鎖課前準備頁。確定結束課程？', '結束課程');
    if (ok != true) return;
    try {
      await _teacher.setPhase(GamePhase.normal);
    } catch (_) {}
    _clearTimers();
    await _refreshPhase();
    if (!mounted) return;
    setState(() {
      _courseStarted = false;
      _tab = 2; // 回到上課古蹟
    });
    _toast('課程已結束');
  }

  Future<bool?> _confirm(String title, String body, String confirmText) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF2A1A0A)),
            child: Text(confirmText,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  String _msg(Object e) => e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('ApiException', '錯誤');

  void _toast(String m) =>
      Fluttertoast.showToast(msg: m, gravity: ToastGravity.BOTTOM);

  static String _phaseName(GamePhase p) => switch (p) {
        GamePhase.quiz1 => '資源採集',
        GamePhase.quiz2 => '攻防戰',
        GamePhase.normal => '平時',
      };

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            _nav(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: _content(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav() {
    final staff = context.watch<AppState>().currentStaff;
    final items = _courseStarted
        ? const [(Icons.flag_rounded, '遊戲階段')]
        : const [
            (Icons.person_add_alt_1_rounded, '學生帳號'),
            (Icons.groups_rounded, '小組設定'),
            (Icons.account_balance_rounded, '上課古蹟'),
            (Icons.quiz_rounded, '題目匯入'),
          ];
    return Container(
      width: 210,
      color: _panel,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Row(
              children: [
                Icon(Icons.school_rounded, color: _gold, size: 24),
                SizedBox(width: 8),
                Text('教師控制台',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text(staff?.displayName ?? '',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: _stageChip(),
          ),
          for (var i = 0; i < items.length; i++)
            _navItem(items[i].$1, items[i].$2, i),
          const Spacer(),
          if (_courseStarted) _runningFooter(),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: Colors.white70),
            label: const Text('登出',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _stageChip() {
    final on = _courseStarted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: on ? _gold.withValues(alpha: 0.16) : _field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: on ? _gold.withValues(alpha: 0.6) : Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.lock_rounded : Icons.edit_note_rounded,
              size: 14, color: on ? _gold : Colors.white54),
          const SizedBox(width: 6),
          Text(on ? '上課中' : '課前準備',
              style: TextStyle(
                  color: on ? _gold : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // 課程控制頁的側欄頁尾：結束課程（重置進度待後端 reset 端點定義後補上）。
  Widget _runningFooter() {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: _endCourse,
        icon: const Icon(Icons.stop_circle_outlined, size: 18, color: _gold),
        label: const Text('結束課程',
            style: TextStyle(
                color: _gold, fontSize: 14, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: _gold)),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final on = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: on ? _gold.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? _gold.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: on ? _gold : Colors.white60),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: on ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    // 課程進行中只剩遊戲階段控制；課前準備才有學生 / 分組 / 古蹟 / 題目。
    if (_courseStarted) return _phaseTab();
    return switch (_tab) {
      0 => _accountsTab(),
      1 => _groupsTab(),
      2 => _heritageTab(),
      _ => _questionsTab(),
    };
  }

  // ── 0：遊戲階段 ───────────────────────────────────────────────────────────────
  Widget _phaseTab() {
    final running = _phaseEndsAt != null;
    return ListView(
      children: [
        _header('遊戲階段控制', '選擇階段；採集 / 攻防會先設定時長再開始，時間到自動回平時',
            trailing: _refreshBtn(_refreshPhase)),
        const SizedBox(height: 16),
        _statusPanel(running),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('選擇階段',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
        _phaseOption(GamePhase.normal, '平時', Icons.pause_circle_outline_rounded,
            '停止採集與攻防，立即回到平時。'),
        const SizedBox(height: 12),
        _phaseOption(GamePhase.quiz1, '資源採集', Icons.spa_rounded,
            '學生答題賺取古蹟原料。點擊後設定時長。'),
        const SizedBox(height: 12),
        _phaseOption(GamePhase.quiz2, '攻防戰', Icons.shield_rounded,
            '各組互相攻擊 / 修復。點擊後設定時長。'),
      ],
    );
  }

  // 目前階段 + 進行中倒數 / 提前結束。
  Widget _statusPanel(bool running) {
    final phaseName = _phase == null ? '讀取中…' : _phaseName(_phase!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: running ? _gold.withValues(alpha: 0.14) : _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: running ? _gold : Colors.white12, width: running ? 2 : 1),
      ),
      child: Row(
        children: [
          Icon(running ? Icons.timer_rounded : Icons.flag_rounded,
              color: running ? _gold : Colors.white60, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('目前階段',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 2),
              Text(phaseName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const Spacer(),
          if (running) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('剩餘時間',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                Text(_fmt(_remaining),
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
              ],
            ),
            const SizedBox(width: 18),
            OutlinedButton.icon(
              onPressed: _busyPhase ? null : () => _startPhase(GamePhase.normal),
              icon:
                  const Icon(Icons.stop_rounded, size: 18, color: Colors.white),
              label:
                  const Text('提前結束', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38)),
            ),
          ],
        ],
      ),
    );
  }

  // 一列階段選項：平時即時停止；採集 / 攻防點擊跳設時長對話框。
  Widget _phaseOption(GamePhase p, String name, IconData icon, String desc) {
    final on = _phase == p;
    return GestureDetector(
      onTap: _busyPhase ? null : () => _onSelectPhase(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: on ? _gold.withValues(alpha: 0.16) : _panel,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: on ? _gold : Colors.white12, width: on ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: on ? _gold : Colors.white70, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: TextStyle(
                              color: on ? _gold : Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                      if (on) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('進行中',
                              style: TextStyle(
                                  color: Color(0xFF2A1A0A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            Icon(
                p == GamePhase.normal
                    ? Icons.chevron_right_rounded
                    : Icons.timer_outlined,
                color: Colors.white38,
                size: 22),
          ],
        ),
      ),
    );
  }

  // ── 1：學生帳號 ───────────────────────────────────────────────────────────────
  Widget _accountsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('學生帳號', '帳號＝姓名_座號、密碼＝座號',
            trailing: _refreshBtn(_refreshStudents)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              if (_locked) _lockBanner('上課中：已停止新增帳號'),
              if (_locked) const SizedBox(height: 16),
              _card(
                '手動新增',
                Row(
                  children: [
                    Expanded(flex: 3, child: _input(_nameCtrl, '姓名')),
                    const SizedBox(width: 12),
                    Expanded(
                        flex: 2, child: _input(_seatCtrl, '座號', number: true)),
                    const SizedBox(width: 12),
                    _primaryBtn('新增', _addStudent, enabled: !_locked),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card(
                '批次匯入（CSV / 貼上）',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每行一位：座號,姓名（例：01,王小明）',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 8),
                    _input(_csvCtrl, '01,王小明\n02,李小花',
                        maxLines: 5, enabled: !_locked),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _primaryBtn('匯入名單', _importCsv, enabled: !_locked),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card('學生名單（${_students.length}）', _studentListView(editable: false)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 2：小組設定（兩區）──────────────────────────────────────────────────────────
  Widget _groupsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('小組設定', '上區：依組別檢視 / 勾選成員；下區：所有學生設定組別',
            trailing: _refreshBtn(_refreshStudents)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              if (_locked) _lockBanner('上課中：已鎖定分組變更'),
              if (_locked) const SizedBox(height: 16),
              _groupDetailRegion(),
              const SizedBox(height: 16),
              _allStudentsRegion(),
            ],
          ),
        ),
      ],
    );
  }

  // 第一區塊：選組別 → 看組名 / 頭像 / 勾選成員
  Widget _groupDetailRegion() {
    final ids = _groupIds;
    final value = ids.contains(_detailGroup) ? _detailGroup : ids.first;
    final members = _students.where((s) => s.groupId == value).toList();
    return _card(
      '小組檢視',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('組別', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              _intDropdown(
                value: value,
                items: ids,
                onChanged: (v) => _selectDetailGroup(v),
                label: (g) => _groupNames[g]?.isNotEmpty == true
                    ? '第 $g 組 · ${_groupNames[g]}'
                    : '第 $g 組',
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _locked ? null : _addGroup,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增小組'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: BorderSide(
                        color: _locked ? Colors.white24 : _gold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 小組頭像（後端端口開發中，先顯示預設）
              Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _field,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        color: Colors.white38, size: 30),
                  ),
                  const SizedBox(height: 4),
                  const Text('組徽（開發中）',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('小組名稱',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _input(_groupNameCtrl, '第 $value 組')),
                        const SizedBox(width: 10),
                        _primaryBtn('儲存', _renameGroup),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 28),
          Text('勾選加入本組的學生（${members.length} 人）',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          if (_loadingStudents)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          else if (_students.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('尚無學生帳號',
                  style: TextStyle(color: Colors.white38)),
            )
          else
            ..._students.map((s) {
              final inGroup = s.groupId == value;
              return _memberCheckRow(s, value, inGroup);
            }),
        ],
      ),
    );
  }

  Widget _memberCheckRow(TeacherStudent s, int group, bool inGroup) {
    return InkWell(
      onTap: _locked
          ? null
          : () => _assignGroup(s, inGroup ? 0 : group),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Checkbox(
              value: inGroup,
              activeColor: _gold,
              checkColor: const Color(0xFF2A1A0A),
              onChanged: _locked
                  ? null
                  : (v) => _assignGroup(s, (v ?? false) ? group : 0),
            ),
            _avatar(s.avatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.name,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
            Text('座號 ${s.seat}',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(width: 10),
            Text(
                s.groupId == 0
                    ? '未分組'
                    : (s.groupId == group ? '本組' : '第 ${s.groupId} 組'),
                style: TextStyle(
                    color: s.groupId == group ? _gold : Colors.white38,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // 第二區塊：所有學生 + 搜尋 + 設定組別
  Widget _allStudentsRegion() {
    final q = _search.trim();
    final filtered = q.isEmpty
        ? _students
        : _students
            .where((s) => s.name.contains(q) || s.seat.contains(q))
            .toList();
    return _card(
      '所有學生（設定組別）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: '搜尋姓名或座號…',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white38),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white38),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
              filled: true,
              fillColor: _field,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingStudents)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(q.isEmpty ? '尚無學生帳號' : '查無符合「$q」的學生',
                  style: const TextStyle(color: Colors.white38)),
            )
          else
            ...filtered.map(_setGroupRow),
        ],
      ),
    );
  }

  Widget _setGroupRow(TeacherStudent s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _avatar(s.avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.name,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Text('座號 ${s.seat}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(width: 12),
          _intDropdown(
            value: s.groupId,
            items: [0, for (var g = 1; g <= _maxGroupOption; g++) g],
            onChanged: _locked ? null : (v) => _assignGroup(s, v),
            label: (g) => g == 0 ? '未分組' : '第 $g 組',
          ),
        ],
      ),
    );
  }

  // ── 學生名單（帳號頁；唯讀）──────────────────────────────────────────────────
  Widget _studentListView({required bool editable}) {
    if (_loadingStudents) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    if (_students.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('尚無學生帳號',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return Column(
      children: [
        for (final s in _students)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                _avatar(s.avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.name,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15)),
                ),
                Text('座號 ${s.seat}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(width: 12),
                Text(s.groupId == 0 ? '未分組' : '第 ${s.groupId} 組',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
                IconButton(
                  onPressed: () => _deleteStudent(s),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white38, size: 20),
                  tooltip: '刪除帳號',
                  splashRadius: 20,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 3：上課古蹟 ───────────────────────────────────────────────────────────────
  /// 解析所選古蹟的 building_id，逐組指派為上課古蹟（全班統一一座）。
  Future<void> _applyHeritageToClass() async {
    if (_applyingHeritage) return;
    setState(() => _applyingHeritage = true);
    try {
      final buildings = await _teacher.listBuildings();
      final match =
          buildings.where((b) => b.name == _selectedHeritage).toList();
      if (match.isEmpty) {
        _toast('後端尚無此古蹟設定，請先在管理者後台建立並儲存');
        return;
      }
      final buildingId = match.first.id;
      final groups = _groupIds;
      var ok = 0;
      for (final g in groups) {
        try {
          await _teacher.setGroupBuilding(groupId: g, buildingId: buildingId);
          ok++;
        } catch (_) {}
      }
      _toast('已將上課古蹟套用到 $ok 組');
      _startCourse(); // 套用後進入課程控制
    } catch (e) {
      _toast('套用失敗：${_msg(e)}');
    } finally {
      if (mounted) setState(() => _applyingHeritage = false);
    }
  }

  Widget _heritageTab() {
    final groupCount = _groupIds.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('上課古蹟', '課前準備最後一步：選一座古蹟套用到全班並開始課程（目前僅開放：北港朝天宮）'),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              childAspectRatio: 0.74,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: mockHeritages.length,
            itemBuilder: (_, i) => _heritageTile(mockHeritages[i]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '開始後會把所選古蹟指派給全班 $groupCount 組，並進入課程控制（期間鎖定分組 / 帳號）。',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            _resetting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.redAccent, strokeWidth: 2.5)),
                  )
                : OutlinedButton.icon(
                    onPressed: _resetProgress,
                    icon: const Icon(Icons.restart_alt_rounded,
                        size: 18, color: Colors.redAccent),
                    label: const Text('重置進度',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                    ),
                  ),
            const SizedBox(width: 12),
            _applyingHeritage
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: _gold, strokeWidth: 2.5)),
                  )
                : _primaryBtn('開始課程', _applyHeritageToClass),
          ],
        ),
      ],
    );
  }

  Widget _heritageTile(HeritageModel h) {
    final enabled = h.id == 'beigang_chaotian_temple';
    final selected = enabled && _selectedHeritage == h.id;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _selectedHeritage = h.id) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (h.cardImagePath.isNotEmpty)
                Image.asset(h.cardImagePath, fit: BoxFit.cover)
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
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: _gold, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(h.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: _gold, size: 20)
                    else if (!enabled)
                      const Icon(Icons.lock_rounded,
                          color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 4：題目匯入（預留）────────────────────────────────────────────────────────
  Widget _questionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('題目匯入', '尚未開放'),
        const SizedBox(height: 16),
        _card(
          '題庫匯入（開發中）',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '之後可在此匯入題目（對應後端 POST /api/question/upload）：\n'
                '題目敘述（文字 / 音檔 / 語音作答）、選項、答案、難度、area。',
                style:
                    TextStyle(color: Colors.white54, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 14),
              _primaryBtn('選擇題目檔案', () {}, enabled: false),
            ],
          ),
        ),
      ],
    );
  }

  // ── 共用元件 ─────────────────────────────────────────────────────────────────
  Widget _avatar(String? url, {double size = 34}) {
    Widget inner;
    if (url == null || url.isEmpty) {
      inner = Icon(Icons.person, size: size * 0.62, color: Colors.white38);
    } else if (url.startsWith('http')) {
      inner = Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Icon(Icons.person, size: size * 0.62, color: Colors.white38));
    } else {
      inner = Image.file(File(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Icon(Icons.person, size: size * 0.62, color: Colors.white38));
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _field,
        border: Border.all(color: Colors.white24),
      ),
      child: ClipOval(child: inner),
    );
  }

  Widget _intDropdown({
    required int value,
    required List<int> items,
    required ValueChanged<int>? onChanged,
    required String Function(int) label,
  }) {
    final safe = items.contains(value) ? value : (items.isEmpty ? 0 : items.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: safe,
          dropdownColor: _panel,
          isDense: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: [
            for (final g in items)
              DropdownMenuItem(value: g, child: Text(label(g))),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      ),
    );
  }

  Widget _lockBanner(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: _gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          Text('（結束上課可解鎖）',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _header(String title, String subtitle, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _refreshBtn(VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
        tooltip: '重新整理',
      );

  Widget _card(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _gold, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, String hint,
      {bool number = false, int maxLines = 1, bool enabled = true}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      enabled: enabled,
      keyboardType: number ? TextInputType.number : TextInputType.multiline,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
        filled: true,
        fillColor: _field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _primaryBtn(String label, VoidCallback onTap, {bool enabled = true}) {
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        foregroundColor: const Color(0xFF2A1A0A),
        disabledBackgroundColor: const Color(0xFF3A352A),
        disabledForegroundColor: Colors.white30,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}
