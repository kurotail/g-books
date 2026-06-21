import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import '../../core/format.dart';
import '../../core/widgets/avatar_image.dart';
import '../../data/heritage_data.dart';
import '../../data/models/group_account.dart';
import '../../data/models/heritage_model.dart';
import '../../data/models/roster_student.dart';
import '../../services/course_session_store.dart';
import '../../services/game_state_service.dart';
import '../../services/question_import.dart';
import '../../services/teacher_service.dart';
import '../../state/app_state.dart';

/// 教師控制台。新模型「一組一帳號 + 班級名冊」：
/// - 班級名冊：管理 students 表（座號 / 姓名 / 頭像），非登入帳號。
/// - 小組帳號：建立各組登入帳號（username 即組名）、指派名冊學生進組。
/// - 上課古蹟：單一古蹟，學生登入時自動綁定，本頁只負責開始 / 結束課程與重置。
/// 操作走 [TeacherService]，目前階段讀 [GameStateService]。
///
/// 「開始上課」後會鎖定結構性設定（名冊 / 帳號 / 分組），避免上課中誤改。
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
  final CourseSessionStore _courseStore = CourseSessionStore();
  String _username = ''; // 目前登入老師（上課場次以此為鍵）

  int _tab = 0;
  // 兩階段：課前準備（名冊 / 帳號 / 上課古蹟）→ 開始課程 → 課程控制（遊戲階段）。
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
  StreamSubscription<GameStateSnapshot>? _stateSub; // 後端階段推播（WS）

  // 班級名冊 + 小組帳號
  List<RosterStudent> _roster = const [];
  List<GroupAccount> _groups = const [];
  bool _loading = false;

  String _selectedHeritage = 'beigang_chaotian_temple';
  bool _resetting = false;

  final _idCtrl = TextEditingController(); // 座號
  final _nameCtrl = TextEditingController(); // 姓名
  final _csvCtrl = TextEditingController();
  final _groupUserCtrl = TextEditingController(); // 組帳號（組名）
  final _groupPassCtrl = TextEditingController(); // 組帳號密碼
  final _searchCtrl = TextEditingController();
  String _search = '';

  // 題庫匯入（ZIP）
  bool _importingQuiz = false;
  String? _importResult; // 匯入結果摘要（成功 / 失敗）
  List<String> _importIssues = const []; // 逐列警告 / 失敗原因

  @override
  void initState() {
    super.initState();
    _teacher = context.read<TeacherService>();
    _gameSvc = context.read<GameStateService>();
    _username = context.read<AppState>().currentStaff?.username ?? '';
    // 訂閱後端階段推播：時間到後端會自動回平時並推播，教師端據此即時對齊（不靠本機
    // 計時器猜測），避免停留在已結束的階段。
    _stateSub = _gameSvc.watch().listen((s) {
      if (mounted) _applySnapshot(s);
    });
    _restoreCourse();
    _refreshData();
  }

  /// 重登還原：本機若有「本帳號開始且未結束」的上課場次，直接回到課程控制頁
  /// （遊戲階段），不退回課前準備。登出不會清除場次，故重登後仍維持上課中。
  /// 先確定上課狀態再載入階段，[_refreshPhase] 會在上課中時依後端剩餘時間接續倒數。
  Future<void> _restoreCourse() async {
    final active = await _courseStore.isActiveFor(_username);
    if (!mounted) return;
    if (active) {
      setState(() {
        _courseStarted = true;
        _tab = 0;
      });
    }
    await _refreshPhase();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _autoTimer?.cancel();
    _ticker?.cancel();
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _csvCtrl.dispose();
    _groupUserCtrl.dispose();
    _groupPassCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 階段 ────────────────────────────────────────────────────────────────────
  /// 取目前階段，並讓倒數一律以後端為準：上課中、採集/攻防且尚有剩餘時間 → 依後端
  /// 剩餘時間（end_time − now）建立 / 對齊本機倒數；否則（平時或已到時）清除。每次
  /// fetch 都重新對齊後端，故老師剛開始、重登接續、手動刷新與學生端的剩餘時間一致。
  Future<void> _refreshPhase() async {
    try {
      final s = await _gameSvc.fetch();
      if (!mounted) return;
      _applySnapshot(s);
    } catch (_) {}
  }

  /// 套用一份後端階段快照（fetch 或 WS 推播皆走此）：以後端為準更新階段，並依剩餘
  /// 時間（end_time − now）建立 / 對齊 / 清除本機倒數。後端到時自動回平時並推播 →
  /// 教師端在此收到 NORMAL，立即離開已結束的階段。
  void _applySnapshot(GameStateSnapshot s) {
    final remaining = s.remaining(DateTime.now());
    final running = _courseStarted && s.isQuiz && remaining > Duration.zero;
    setState(() {
      _phase = s.phase;
      if (running) {
        _startTimers(remaining);
      } else {
        _clearTimers();
      }
    });
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
        // 不在本機自算倒數：setPhase 已把 end_time 寫進後端，倒數一律由下方
        // _refreshPhase fetch 回來依後端剩餘時間建立（與學生端同步）。
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

  /// 本機倒數歸零：不在前端強制改階段，改為重新 fetch 後端權威狀態（後端到 end_time
  /// 會自動回平時；若因時鐘誤差後端尚有剩餘時間，[_applySnapshot] 會用真正的剩餘時間
  /// 續算，不會誤停）。WS 推播稍後也會補上 NORMAL。
  Future<void> _autoEnd() async {
    if (_phaseEndsAt == null) return;
    _clearTimers();
    await _refreshPhase();
    if (mounted) _toast('時間到，已重新讀取階段狀態');
  }

  Duration get _remaining {
    final e = _phaseEndsAt;
    if (e == null) return Duration.zero;
    final r = e.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  // ── 名冊 / 小組 ───────────────────────────────────────────────────────────────
  Future<void> _refreshData() async {
    setState(() => _loading = true);
    try {
      final roster = await _teacher.listRoster();
      final groups = await _teacher.listGroups();
      if (mounted) {
        setState(() {
          _roster = roster;
          _groups = groups;
        });
      }
    } catch (e) {
      _toast('讀取資料失敗：${_msg(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 名冊學生目前所屬的組（username；未分組回空字串）。
  String _groupOfStudent(int id) {
    for (final g in _groups) {
      if (g.studentIds.contains(id)) return g.username;
    }
    return '';
  }

  Future<void> _addStudent() async {
    if (_locked) return;
    final seatText = _idCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final seatNo = int.tryParse(seatText);
    if (seatNo == null || seatNo <= 0 || name.isEmpty) {
      _toast('請輸入有效座號與姓名');
      return;
    }
    try {
      await _teacher.createStudent(seatNo: seatNo, name: name);
      _idCtrl.clear();
      _nameCtrl.clear();
      await _refreshData();
      _toast('已新增 $name（座號 $seatNo）');
    } catch (e) {
      _toast('新增失敗：${_msg(e)}');
    }
  }

  /// 貼上文字匯入（沿用文字框內容）。
  Future<void> _importPastedRoster() async {
    if (_locked) return;
    if (_csvCtrl.text.trim().isEmpty) {
      _toast('請先貼上名單');
      return;
    }
    // 貼上的文字沒有欄名列。
    final (created, skipped) =
        await _importRosterText(_csvCtrl.text, skipHeader: false);
    _csvCtrl.clear();
    await _refreshData();
    _toast('匯入完成：新增 $created 筆，略過 $skipped 筆');
  }

  /// 上傳 CSV 檔匯入（欄位：座號,姓名）。與貼上匯入共用 [_importRosterText] 解析。
  Future<void> _pickAndImportRosterCsv() async {
    if (_locked) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (picked == null) return; // 使用者取消
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      _toast('讀取檔案失敗');
      return;
    }
    // 容許 UTF-8 BOM。
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    // CSV 檔第一列固定是欄名（座號,姓名），略過。
    final (created, skipped) = await _importRosterText(text, skipHeader: true);
    await _refreshData();
    _toast('匯入完成：新增 $created 筆，略過 $skipped 筆');
  }

  /// 解析「座號,姓名」名單文字並逐筆建立。回傳 (成功數, 略過數)。座號在前或姓名在前、
  /// 逗號或 Tab 分隔皆可。[skipHeader] 為 true 時略過第一列（CSV 檔的欄名列）；貼上文字
  /// 沒有欄名列，傳 false。另保留「整列含『座號/姓名』字樣即視為欄名」的防呆。
  Future<(int created, int skipped)> _importRosterText(
    String text, {
    required bool skipHeader,
  }) async {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    var created = 0, skipped = 0;
    for (var li = (skipHeader && lines.isNotEmpty) ? 1 : 0;
        li < lines.length;
        li++) {
      final line = lines[li];
      final parts = line.split(RegExp(r'[,\t]')).map((p) => p.trim()).toList();
      if (parts.length < 2) {
        skipped++;
        continue;
      }
      if (parts.any((p) => p.contains('座號') || p.contains('姓名'))) continue;
      final firstIsId = RegExp(r'^\d+$').hasMatch(parts[0]);
      final seatText = firstIsId ? parts[0] : parts[1];
      final name = firstIsId ? parts[1] : parts[0];
      final seatNo = int.tryParse(seatText);
      if (seatNo == null || seatNo <= 0 || name.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await _teacher.createStudent(seatNo: seatNo, name: name);
        created++;
      } catch (_) {
        skipped++;
      }
    }
    return (created, skipped);
  }

  Future<void> _deleteStudent(RosterStudent s) async {
    final ok = await _confirm(
        '刪除學生', '確定從名冊刪除「${s.name}（座號 ${s.seatNo}）」？會一併從各組移除。', '刪除');
    if (ok != true) return;
    try {
      await _teacher.deleteStudent(id: s.id);
      await _refreshData();
      _toast('已刪除 ${s.name}');
    } catch (e) {
      _toast('刪除失敗：${_msg(e)}');
    }
  }

  Future<void> _addGroup() async {
    if (_locked) return;
    final user = _groupUserCtrl.text.trim();
    final pass = _groupPassCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      _toast('請輸入組名（帳號）與密碼');
      return;
    }
    try {
      await _teacher.createGroup(username: user, password: pass);
      _groupUserCtrl.clear();
      _groupPassCtrl.clear();
      await _refreshData();
      _toast('已建立小組帳號「$user」');
    } catch (e) {
      _toast('建立失敗：${_msg(e)}');
    }
  }

  Future<void> _deleteGroup(GroupAccount g) async {
    if (_locked) return;
    final ok =
        await _confirm('刪除小組帳號', '確定刪除小組帳號「${g.username}」？名冊學生不受影響。', '刪除');
    if (ok != true) return;
    try {
      await _teacher.deleteGroup(userId: g.id);
      await _refreshData();
      _toast('已刪除「${g.username}」');
    } catch (e) {
      _toast('刪除失敗：${_msg(e)}');
    }
  }

  /// 把學生指派到 [target] 組（target 空字串 = 未分組）。為維持「一人一組」，
  /// 會把該學生從其他組移除、加入目標組（只對有變動的組打 API）。
  Future<void> _assignStudent(RosterStudent s, String target) async {
    if (_locked) return;
    try {
      for (final g in List<GroupAccount>.from(_groups)) {
        final has = g.studentIds.contains(s.id);
        final want = g.username == target;
        if (has == want) continue;
        final ids = List<int>.from(g.studentIds);
        if (want) {
          ids.add(s.id);
        } else {
          ids.remove(s.id);
        }
        ids.sort();
        await _teacher.setGroupStudents(userId: g.id, studentIds: ids);
      }
      await _refreshData();
    } catch (e) {
      _toast('指派失敗：${_msg(e)}');
    }
  }

  /// 重置（全清）：刪除全部小組帳號與全部名冊學生。古蹟設定與題庫保留。
  Future<void> _resetProgress() async {
    final gN = _groups.length, sN = _roster.length;
    if (gN == 0 && sN == 0) {
      _toast('目前沒有資料');
      return;
    }
    final ok = await _confirm('重置（全清）',
        '將刪除全部 $gN 個小組帳號與 $sN 位名冊學生。古蹟設定與題庫會保留。確定？', '全部刪除');
    if (ok != true) return;
    setState(() => _resetting = true);
    try {
      for (final g in List<GroupAccount>.from(_groups)) {
        try {
          await _teacher.deleteGroup(userId: g.id);
        } catch (_) {}
      }
      for (final s in List<RosterStudent>.from(_roster)) {
        try {
          await _teacher.deleteStudent(id: s.id);
        } catch (_) {}
      }
      await _refreshData();
      _toast('已重置（全清）');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  /// 進入課程控制。鎖定準備頁、切到遊戲階段。學生端登入時自動綁定古蹟，故此處
  /// 不需逐組指派 building。
  void _startCourse() {
    setState(() {
      _courseStarted = true;
      _tab = 0;
    });
    _courseStore.start(_username); // 記住場次，供登出重登還原
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
    await _courseStore.end(); // 清掉本機場次，重登不再回到上課頁
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
            (Icons.badge_rounded, '班級名冊'),
            (Icons.groups_rounded, '小組帳號'),
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

  // 課程控制頁的側欄頁尾：結束課程。
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
    // 課程進行中只剩遊戲階段控制；課前準備才有名冊 / 帳號 / 古蹟 / 題目。
    if (_courseStarted) return _phaseTab();
    return switch (_tab) {
      0 => _rosterTab(),
      1 => _groupsTab(),
      2 => _heritageTab(),
      _ => _questionsTab(),
    };
  }

  // ── 遊戲階段 ───────────────────────────────────────────────────────────────
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
                Text(formatMmSs(_remaining),
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

  // ── 班級名冊 ─────────────────────────────────────────────────────────────────
  Widget _rosterTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('班級名冊', '管理學生（座號 / 姓名 / 頭像）；學生由小組帳號登入，名冊本身非帳號',
            trailing: _refreshBtn(_refreshData)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              if (_locked) _lockBanner('上課中：已停止編輯名冊'),
              if (_locked) const SizedBox(height: 16),
              _card(
                '手動新增',
                Row(
                  children: [
                    Expanded(
                        flex: 2, child: _input(_idCtrl, '座號', number: true)),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _input(_nameCtrl, '姓名')),
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
                    const Text('每行一位：座號,姓名（例：01,王小明）。可貼上文字，或上傳 .csv 檔。',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 8),
                    _input(_csvCtrl, '01,王小明\n02,李小花',
                        maxLines: 5, enabled: !_locked),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _locked ? null : _pickAndImportRosterCsv,
                          icon: const Icon(Icons.upload_file_rounded,
                              size: 18, color: _gold),
                          label: const Text('上傳 CSV 檔',
                              style: TextStyle(
                                  color: _gold, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _gold),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _primaryBtn('匯入貼上名單', _importPastedRoster,
                            enabled: !_locked),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card('學生名冊（${_roster.length}）', _rosterListView()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rosterListView() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    if (_roster.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('尚無名冊學生',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return Column(
      children: [
        for (final s in _roster)
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
                Text('座號 ${s.seatNo}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(width: 12),
                Builder(builder: (_) {
                  final g = _groupOfStudent(s.id);
                  return Text(g.isEmpty ? '未分組' : g,
                      style: TextStyle(
                          color: g.isEmpty ? Colors.white38 : Colors.white54,
                          fontSize: 13));
                }),
                IconButton(
                  onPressed: _locked ? null : () => _deleteStudent(s),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white38, size: 20),
                  tooltip: '刪除學生',
                  splashRadius: 20,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 小組帳號 ─────────────────────────────────────────────────────────────────
  Widget _groupsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('小組帳號', '建立各組登入帳號（帳號＝組名），並把名冊學生指派進組',
            trailing: _refreshBtn(_refreshData)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              if (_locked) _lockBanner('上課中：已鎖定帳號與分組'),
              if (_locked) const SizedBox(height: 16),
              _card(
                '建立小組帳號',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('帳號＝組名（學生用此登入）；密碼自訂',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: _input(_groupUserCtrl, '組名 / 帳號')),
                        const SizedBox(width: 12),
                        Expanded(
                            flex: 2, child: _input(_groupPassCtrl, '密碼')),
                        const SizedBox(width: 12),
                        _primaryBtn('建立', _addGroup, enabled: !_locked),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card('小組帳號（${_groups.length}）', _groupListView()),
              const SizedBox(height: 16),
              _card('指派學生到小組', _assignRegion()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupListView() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    if (_groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('尚無小組帳號', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: [
        for (final g in _groups)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                _avatar(g.avatarUrl, fallback: Icons.groups_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(g.username,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15)),
                ),
                Text('${g.studentIds.length} 人',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 12),
                Text(g.buildingId > 0 ? '已綁古蹟' : '未綁古蹟',
                    style: TextStyle(
                        color:
                            g.buildingId > 0 ? _gold : Colors.white38,
                        fontSize: 12)),
                IconButton(
                  onPressed: _locked ? null : () => _deleteGroup(g),
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

  // 指派區：搜尋 + 每位名冊學生一個「屬於哪一組」下拉。
  Widget _assignRegion() {
    final q = _search.trim();
    final filtered = q.isEmpty
        ? _roster
        : _roster
            .where((s) => s.name.contains(q) || '${s.seatNo}'.contains(q))
            .toList();
    final usernames = [for (final g in _groups) g.username];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: '搜尋姓名或座號…',
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38),
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _gold)),
          )
        else if (_groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('請先建立小組帳號', style: TextStyle(color: Colors.white38)),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(q.isEmpty ? '尚無名冊學生' : '查無符合「$q」的學生',
                style: const TextStyle(color: Colors.white38)),
          )
        else
          ...filtered.map((s) => _assignRow(s, usernames)),
      ],
    );
  }

  Widget _assignRow(RosterStudent s, List<String> usernames) {
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
          Text('座號 ${s.seatNo}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(width: 12),
          _groupDropdown(
            value: _groupOfStudent(s.id),
            usernames: usernames,
            onChanged: _locked ? null : (v) => _assignStudent(s, v),
          ),
        ],
      ),
    );
  }

  // ── 上課古蹟 ───────────────────────────────────────────────────────────────
  Widget _heritageTab() {
    final groupCount = _groups.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('上課古蹟',
            '課前準備最後一步：確認古蹟並開始課程（學生登入時自動綁定；目前僅開放：北港朝天宮）'),
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
                '開始後進入課程控制（期間鎖定名冊 / 帳號 / 分組）。目前共 $groupCount 個小組帳號。',
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
                    label: const Text('重置（全清）',
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
            _primaryBtn('開始課程', _startCourse),
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

  // ── 題目匯入（ZIP：quest.csv + audio/）─────────────────────────────────────
  /// 選一個 .zip（內含 quest.csv 與 audio/），解析 → 上傳音檔 → 批次上傳題目。
  Future<void> _pickAndImportQuiz() async {
    if (_importingQuiz) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (picked == null) return; // 使用者取消
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      _toast('讀取檔案失敗');
      return;
    }

    setState(() {
      _importingQuiz = true;
      _importResult = null;
      _importIssues = const [];
    });
    final issues = <String>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1) 找 quest.csv → 解析 → 分配 area。
      final csvFile = _findInArchive(
        archive,
        (n) => n.toLowerCase().endsWith('quest.csv'),
      );
      if (csvFile == null) {
        throw const FormatException('ZIP 內找不到 quest.csv');
      }
      final parsed = parseQuestCsv(utf8.decode(csvFile.content as List<int>));
      assignAreas(parsed.rows);
      issues.addAll(parsed.warnings);

      // 2) 上傳所有被引用到的音檔，建立「相對路徑 → 已上傳 URL」對照。
      final audioUrls = <String, String>{};
      for (final ref in parsed.audioRefs) {
        final entry = _findAudioEntry(archive, ref);
        if (entry == null) {
          issues.add('找不到音檔：$ref（請確認在 ZIP 的 audio/ 內）');
          continue;
        }
        audioUrls[ref] = await _teacher.uploadQuestionAudio(
          entry.content as List<int>,
          _basename(ref),
        );
      }

      // 3) 逐列建 payload；缺音檔或格式錯的列略過並記錄。
      final payloads = <Map<String, dynamic>>[];
      var voiceCount = 0;
      for (final row in parsed.rows) {
        try {
          final p = buildQuestionPayload(row, (v) {
            final url = audioUrls[v.trim()];
            if (url == null) throw FormatException('音檔未上傳：$v');
            return url;
          });
          if ((p['answer'] as Map)['type'] == 'voice_response') voiceCount++;
          payloads.add(p);
        } on FormatException catch (e) {
          issues.add('第 ${row.line} 列略過：${e.message}');
        }
      }
      if (payloads.isEmpty) {
        throw const FormatException('沒有可上傳的題目');
      }

      // 4) 批次上傳。
      final results = await _teacher.uploadQuestions(payloads);
      final created = results.where((r) => r.created).length;
      for (final r in results) {
        if (!r.created) {
          issues.add('上傳第 ${r.index} 題失敗（${r.status}）：${r.error ?? ''}');
        }
      }
      final sb = StringBuffer('成功匯入 $created / ${payloads.length} 題');
      if (voiceCount > 0) {
        sb.write('\n（含 $voiceCount 題語音作答；以辨識文字比對評分）');
      }
      if (mounted) setState(() => _importResult = sb.toString());
    } catch (e) {
      issues.add(e is FormatException ? e.message : '$e');
      if (mounted) setState(() => _importResult = '匯入失敗');
    } finally {
      if (mounted) {
        setState(() {
          _importingQuiz = false;
          _importIssues = issues;
        });
      }
    }
  }

  /// 在壓縮檔內找符合 [test] 且路徑最短的檔案（最短＝最接近根、最不易誤判）。
  ArchiveFile? _findInArchive(Archive a, bool Function(String name) test) {
    ArchiveFile? best;
    var bestLen = 1 << 30;
    for (final f in a.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (test(name) && name.length < bestLen) {
        best = f;
        bestLen = name.length;
      }
    }
    return best;
  }

  /// 依優先序把 quest.csv 的音檔欄位（相對 audio/ 的路徑）對到壓縮檔內的檔案。
  ArchiveFile? _findAudioEntry(Archive a, String value) {
    final v = value.trim().replaceAll('\\', '/');
    final base = _basename(v);
    for (final test in <bool Function(String)>[
      (n) => n.endsWith('audio/$v'),
      (n) => n == 'audio/$v',
      (n) => n.endsWith('/$v'),
      (n) => n == v,
      (n) => _basename(n) == base,
    ]) {
      final f = _findInArchive(a, test);
      if (f != null) return f;
    }
    return null;
  }

  String _basename(String p) {
    final n = p.replaceAll('\\', '/');
    final i = n.lastIndexOf('/');
    return i < 0 ? n : n.substring(i + 1);
  }

  Widget _questionsTab() {
    return ListView(
      children: [
        _header('題目匯入', '從 ZIP 匯入題庫（quest.csv + audio/）'),
        const SizedBox(height: 16),
        _card(
          '題庫 ZIP 匯入',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ZIP 內需含 quest.csv 與 audio/ 資料夾。\n'
                'quest.csv 欄位：題目, A, B, C, D, 答案, 難度（首列為欄名）。\n'
                '• 一般選擇題：A~D 填文字、答案填 A/B/C/D\n'
                '• 語音選項題：A~D 填音檔（如 A.wav）、答案填正確選項字母\n'
                '• 語音作答題：A~D 留空、答案填參考音檔（如 q1.wav）\n'
                '音檔放 audio/ 下，欄位填相對路徑（a.mp3 或 abc/b.mp3）。\n'
                '各難度約 75% 進採集、25% 進攻防戰。',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13.5,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _primaryBtn(
                    _importingQuiz ? '匯入中…' : '選擇題目 ZIP',
                    _pickAndImportQuiz,
                    enabled: !_importingQuiz && !_locked,
                  ),
                  if (_importingQuiz) ...[
                    const SizedBox(width: 14),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    ),
                  ],
                ],
              ),
              if (_importResult != null) ...[
                const SizedBox(height: 16),
                Text(
                  _importResult!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              if (_importIssues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '需注意（${_importIssues.length}）：',
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final m in _importIssues.take(50))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $m',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          '提醒',
          const Text(
            '匯入會「新增」題目到題庫（不會清除既有題目），重複匯入會產生重複題。\n'
            '語音作答題目前可匯入，但後端尚未支援以參考音檔自動評分。',
            style: TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.6),
          ),
        ),
      ],
    );
  }

  // ── 共用元件 ─────────────────────────────────────────────────────────────────
  Widget _avatar(String? rawUrl,
      {double size = 34, IconData fallback = Icons.person}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _field,
        border: Border.all(color: Colors.white24),
      ),
      child: ClipOval(
        child: AvatarImage(
          url: rawUrl,
          width: size,
          height: size,
          placeholder:
              Icon(fallback, size: size * 0.62, color: Colors.white38),
        ),
      ),
    );
  }

  // 「屬於哪一組」下拉：value 為組名（空字串 = 未分組）。
  Widget _groupDropdown({
    required String value,
    required List<String> usernames,
    required ValueChanged<String>? onChanged,
  }) {
    final items = ['', ...usernames];
    final safe = items.contains(value) ? value : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safe,
          dropdownColor: _panel,
          isDense: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: [
            for (final u in items)
              DropdownMenuItem(value: u, child: Text(u.isEmpty ? '未分組' : u)),
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
