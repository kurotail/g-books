import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/format.dart';
import '../../data/component_data.dart';
import '../../data/heritage_data.dart';
import '../../data/models/component_model.dart';
import '../../data/models/heritage_model.dart';
import '../../data/models/user_model.dart';
import '../../state/app_state.dart';
import '../../state/heritage_board_controller.dart';
import '../../services/game_state_service.dart';
import '../../services/quiz_service.dart';
import '../../services/collection_progress_service.dart';
import 'widgets/banner_intro.dart';
import 'widgets/framed_component_tile.dart';

/// 資源採集（遊戲階段 quiz1）。進場 fetch 遊戲狀態 → 依開始時間倒數；時間內回合
/// 不斷循環：回合開場動畫 → 選原料採集關卡難度 → 取題作答（選擇 / 語音）→ 答對發原料。
/// 時間到強制結束，提供「返回我的古蹟 / 前往編輯」。
class ResourceCollectionScreen extends StatefulWidget {
  const ResourceCollectionScreen({super.key});

  @override
  State<ResourceCollectionScreen> createState() =>
      _ResourceCollectionScreenState();
}

enum _Phase { roundIntro, picking, loadingQ, answering, result, timeUp }

class _ResourceCollectionScreenState extends State<ResourceCollectionScreen> {
  // 服務 / 狀態（initState 取得，避免 await 後再用 context）。
  late final GameStateService _gameSvc;
  late final QuizService _quizSvc;
  late final HeritageBoardController _board;
  late final AppState _appState;
  late final CollectionProgressService _progressSvc;

  GameStateSnapshot? _state;
  StreamSubscription<GameStateSnapshot>? _stateSub;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  bool _ready = false; // 遊戲狀態 + 回合進度載入完成前不顯示主流程
  String _sessionKey = ''; // 採集場次識別（階段開始時間 ISO）
  _Phase _phase = _Phase.roundIntro;
  int _round = 1;
  int _difficulty = 1; // 1=易 2=中 3=難

  QuizQuestion? _q;
  int? _selected; // 選擇題選中的選項
  bool _submitting = false;
  QuizResult? _result;
  ComponentModel? _reward;

  // 語音作答。
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  String? _recordedPath;
  bool _assetsPrecached = false;

  static const _areaKeys = ['easy', 'mid', 'hard'];
  static const Map<String, List<String>> _areaNames = {
    'beigang_chaotian_temple': ['宮廟城牆', '廟埕廣場', '神明廳堂'],
  };

  @override
  void initState() {
    super.initState();
    _gameSvc = context.read<GameStateService>();
    _quizSvc = context.read<QuizService>();
    _board = context.read<HeritageBoardController>();
    _appState = context.read<AppState>();
    _progressSvc = context.read<CollectionProgressService>();
    _initGameState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsPrecached) return;
    _assetsPrecached = true;
    for (final k in _areaKeys) {
      precacheImage(
        AssetImage('assets/heritages/$_hid/area/$k.png'),
        context,
        onError: (_, _) {},
      );
    }
    precacheImage(const AssetImage('assets/icons/star.png'), context,
        onError: (_, _) {});
    precacheImage(const AssetImage('assets/icons/times_up.png'), context,
        onError: (_, _) {});
  }

  Future<void> _initGameState() async {
    final snap = await _gameSvc.fetch();
    // 依場次（階段開始時間）解析回合：同場次接續先前回合；新場次從第 1 回合開始。
    final sessionKey = snap.startTime.toIso8601String();
    final saved = await _progressSvc.load();
    int round;
    if (saved != null && saved.sessionKey == sessionKey) {
      round = saved.round < 1 ? 1 : saved.round;
    } else {
      round = 1;
      await _progressSvc.save(
        CollectionProgress(sessionKey: sessionKey, round: 1),
      );
    }
    if (!mounted) return;
    setState(() {
      _state = snap;
      _sessionKey = sessionKey;
      _round = round;
      _remaining = snap.remaining(DateTime.now());
      _phase = _Phase.roundIntro;
      _ready = true;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    // 訂閱老師端推播：階段 / 開始時間變更時更新倒數。
    _stateSub = _gameSvc.watch().listen((snap) {
      if (!mounted) return;
      setState(() => _state = snap);
    });
  }

  void _tick() {
    final st = _state;
    if (st == null) return;
    final rem = st.remaining(DateTime.now());
    if (rem != _remaining) setState(() => _remaining = rem);
    if (rem == Duration.zero && _phase != _Phase.timeUp) _goTimeUp();
  }

  Future<void> _goTimeUp() async {
    _ticker?.cancel();
    if (_recording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _remaining = Duration.zero;
      _phase = _Phase.timeUp;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stateSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── 古蹟 / 組員 / 回合 ──────────────────────────────────────────────────────

  String get _hid {
    if (_board.heritageId.isNotEmpty) return _board.heritageId;
    return mockHeritages
        .firstWhere(
          (h) => h.status == HeritageStatus.assigned,
          orElse: () => mockHeritages.first,
        )
        .id;
  }

  List<UserModel> get _members => _appState.groupMembers;

  /// 答題組員依小組名單依序輪流（回合 1→第一位，超過人數則回繞）。
  String get _memberLetter {
    final n = _members.length;
    if (n == 0) return 'A';
    return String.fromCharCode(65 + (_round - 1) % n);
  }

  String get _answererLabel {
    final n = _members.length;
    final name = n == 0 ? '組長' : _members[(_round - 1) % n].name;
    return '組員$_memberLetter：$name';
  }

  static const _cnDigits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  static String _cn(int n) {
    if (n <= 0) return '零';
    if (n < 10) return _cnDigits[n];
    if (n < 20) return '十${n % 10 == 0 ? '' : _cnDigits[n % 10]}';
    final t = n ~/ 10, o = n % 10;
    return '${_cnDigits[t]}十${o == 0 ? '' : _cnDigits[o]}';
  }

  // ── 流程 ────────────────────────────────────────────────────────────────────

  Future<void> _pickDifficulty(int diff) async {
    if (_phase != _Phase.picking) return;
    setState(() {
      _difficulty = diff;
      _phase = _Phase.loadingQ;
    });
    try {
      final q = await _quizSvc.fetchQuestion(heritageId: _hid, difficulty: diff);
      if (!mounted) return;
      setState(() {
        _q = q;
        _selected = null;
        _recordedPath = null;
        _recording = false;
        _phase = _Phase.answering;
      });
    } catch (_) {
      if (!mounted) return;
      _toast('取題失敗，請再試一次');
      setState(() => _phase = _Phase.picking);
    }
  }

  Future<void> _submitChoice() async {
    if (_selected == null || _submitting || _q == null) return;
    setState(() => _submitting = true);
    final res =
        await _quizSvc.submitAnswer(QuizAnswer.choice(_q!.session, _selected!));
    await _handleResult(res);
  }

  Future<void> _submitAudio() async {
    final path = _recordedPath;
    if (path == null || _submitting || _q == null) return;
    setState(() => _submitting = true);
    String b64;
    try {
      b64 = base64Encode(await File(path).readAsBytes());
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('讀取錄音失敗');
      return;
    }
    final res = await _quizSvc.submitAnswer(QuizAnswer.audio(_q!.session, b64));
    await _handleResult(res);
  }

  Future<void> _handleResult(QuizResult res) async {
    ComponentModel? reward;
    if (res.correct) {
      if (res.itemId != null) {
        // 後端：物品已由伺服器入庫，刷新背包後依 item_id 查出對應原料。
        await _board.refresh();
        final type = _board.typeOfItemId(res.itemId!);
        reward = type != null ? componentById(_hid, type) : null;
      } else {
        // 本機 mock：依難度隨機發一個對應等級的原料到背包。
        reward = await _board.grantRandomOfLevel(_difficulty);
      }
    }
    if (!mounted) return;
    setState(() {
      _result = res;
      _reward = reward;
      _submitting = false;
      _phase = _Phase.result;
    });
  }

  void _nextRound() {
    setState(() {
      _round++;
      _q = null;
      _selected = null;
      _recordedPath = null;
      _recording = false;
      _result = null;
      _reward = null;
      _phase = _Phase.roundIntro;
    });
    // 持久化新回合：中途跳出 App、重啟後可接續此回合。
    _progressSvc.save(CollectionProgress(sessionKey: _sessionKey, round: _round));
  }

  // ── 語音 ────────────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_recording || _phase != _Phase.answering) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('需要麥克風權限才能錄音');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/answer_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordedPath = null;
      });
    } catch (_) {
      if (mounted) _toast('無法開始錄音');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordedPath = path;
      });
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _playUrl(String url) async {
    try {
      await _player.stop();
      await _player.play(UrlSource(url));
    } catch (_) {
      _toast('語音載入失敗（mock 無音檔）');
    }
  }

  Future<void> _playFile(String path) async {
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      _toast('無法播放錄音');
    }
  }

  void _toast(String msg) => Fluttertoast.showToast(
        msg: msg,
        gravity: ToastGravity.CENTER,
      );

  // ── build ───────────────────────────────────────────────────────────────────

  /// 取題作答中（loadingQ / answering / result）不可離開——必須作答完成；
  /// 其餘階段（開場 / 選關卡 / 時間到）才允許返回鍵離開。
  bool get _canLeave =>
      _phase == _Phase.roundIntro ||
      _phase == _Phase.picking ||
      _phase == _Phase.timeUp;

  @override
  Widget build(BuildContext context) {
    // 載入遊戲狀態 + 回合進度前，僅顯示底圖與轉圈，避免回合數先以 1 顯示再跳動。
    if (!_ready) {
      return Scaffold(
        backgroundColor: const Color(0xFF15110C),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/bg_login.png', fit: BoxFit.cover),
            const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A843)),
            ),
          ],
        ),
      );
    }
    // 監聽背包以即時更新各關卡的採集進度。
    context.watch<HeritageBoardController>();
    return PopScope(
      canPop: _canLeave,
      // 被擋下時不做任何事：答題中無法以返回鍵離開。
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: const Color(0xFF15110C),
        body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/bg_login.png',
              fit: BoxFit.cover, gaplessPlayback: true),
          const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
          SafeArea(child: _body()),
          _topBar(),
          if (_phase == _Phase.roundIntro)
            BannerIntro(
              key: ValueKey(_round),
              title: '回 合 ${_cn(_round)}',
              subtitle: '$_answererLabel 答題',
              onCompleted: () {
                if (mounted && _phase == _Phase.roundIntro) {
                  setState(() => _phase = _Phase.picking);
                }
              },
            ),
          if (_phase == _Phase.loadingQ) _loadingOverlay(),
          if (_phase == _Phase.result) _resultOverlay(),
          if (_phase == _Phase.timeUp) _timeUpOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.picking:
        return _pickingView();
      case _Phase.answering:
        return _answeringView();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 上方資訊列：倒數（置中）＋ 回合 / 答題者（右側）─────────────────────────────
  Widget _topBar() {
    final showRound =
        _phase == _Phase.picking || _phase == _Phase.answering;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _countdownPill(),
              if (showRound)
                Align(alignment: Alignment.centerRight, child: _roundPill()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countdownPill() {
    final low = _remaining.inSeconds <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF0241F19),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55D4A843)),
      ),
      child: Text(
        formatMmSs(_remaining),
        style: TextStyle(
          color: low ? const Color(0xFFFF6B5E) : const Color(0xFFE8DCC0),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 6,
        ),
      ),
    );
  }

  Widget _roundPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE6241F19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('回合 $_round',
              style: const TextStyle(
                color: Color(0xFFD4A843),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              )),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 1,
            height: 16,
            color: Colors.white24,
          ),
          Text('$_answererLabel答題',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  // ── 原料採集關卡（難度）選擇 ──────────────────────────────────────────────────
  Widget _pickingView() {
    final names = _areaNames[_hid] ?? const ['初級原料', '中級原料', '高級原料'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 64, 40, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('原料採集關卡',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              )),
          const SizedBox(height: 6),
          const Text('請選擇你想收集古蹟原料等級，星星數越多採集難度越高',
              style: TextStyle(color: Colors.white60, fontSize: 15)),
          Expanded(
            child: Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var d = 1; d <= 3; d++) ...[
                    if (d > 1) const SizedBox(width: 22),
                    Expanded(
                      child: _DifficultyCard(
                        name: names[d - 1],
                        imagePath:
                            'assets/heritages/$_hid/area/${_areaKeys[d - 1]}.png',
                        stars: d,
                        progress: _progressOf(d),
                        onTap: () => _pickDifficulty(d),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 該難度（等級）已採集 / 總數，供關卡卡片顯示進度。
  String _progressOf(int diff) {
    final comps = componentsByLevel(_hid, diff);
    final total = comps.length;
    final owned = comps
        .where((c) => _board.qty(c.id) > 0 || _board.slots.containsValue(c.id))
        .length;
    return '$owned / $total';
  }

  // ── 答題 ────────────────────────────────────────────────────────────────────
  Widget _answeringView() {
    final q = _q;
    if (q == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Expanded(child: Center(child: _promptArea(q))),
          _answerPanel(q),
        ],
      ),
    );
  }

  Widget _promptArea(QuizQuestion q) {
    if (q.prompt.isAudio) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('請聆聽題目後作答',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => _playUrl(q.prompt.data),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xF0241F19),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFD4A843)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_up_rounded,
                      color: Color(0xFFD4A843), size: 24),
                  SizedBox(width: 10),
                  Text('播放語音題目',
                      style: TextStyle(
                        color: Color(0xFFE8DCC0),
                        fontSize: 18,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        q.prompt.data,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          height: 1.5,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 12, offset: Offset(1, 2)),
          ],
        ),
      ),
    );
  }

  Widget _answerPanel(QuizQuestion q) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: const BoxDecoration(
        color: Color(0xF2CDB590),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: q.isChoice
            ? _choicePanel(q.choices!.data)
            : _recordPanel(),
      ),
    );
  }

  Widget _choicePanel(List<String> choices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ChoiceTile(
            index: i,
            text: choices[i],
            selected: _selected == i,
            onTap: _submitting ? null : () => setState(() => _selected = i),
          ),
        ],
        const SizedBox(height: 18),
        // 選了題目（拿到題）後即須作答，不提供離開鈕。
        Center(
          child: _panelAction(
            label: '確 認',
            enabled: _selected != null && !_submitting,
            onTap: _submitChoice,
          ),
        ),
      ],
    );
  }

  Widget _recordPanel() {
    final hasClip = _recordedPath != null && !_recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => _startRecording(),
          onTapUp: (_) => _stopRecording(),
          onTapCancel: _stopRecording,
          child: _MicButton(recording: _recording),
        ),
        const SizedBox(height: 12),
        Text(
          _recording
              ? '錄音中…放開即停止'
              : (hasClip ? '已錄好，可試聽或送出' : '按壓麥克風，並說出你的答案'),
          style: const TextStyle(
            color: Color(0xFF4A3A28),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasClip) ...[
              _smallPill(
                icon: Icons.play_arrow_rounded,
                label: '試聽',
                onTap: () => _playFile(_recordedPath!),
              ),
              const SizedBox(width: 14),
            ],
            _panelAction(
              label: '送 出',
              enabled: hasClip && !_submitting,
              onTap: _submitAudio,
            ),
          ],
        ),
      ],
    );
  }

  Widget _panelAction({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF241F19),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFD4A843), width: 1.4),
          ),
          child: _submitting && enabled
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Color(0xFFD4A843)),
                )
              : Text(label,
                  style: const TextStyle(
                    color: Color(0xFFE8DCC0),
                    fontSize: 18,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  )),
        ),
      ),
    );
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x33241F19),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF8A6A40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF4A3A28), size: 20),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                  color: Color(0xFF4A3A28),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }

  // ── overlays ─────────────────────────────────────────────────────────────────
  Widget _loadingOverlay() {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0x66000000),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFD4A843)),
        ),
      ),
    );
  }

  Widget _resultOverlay() {
    final correct = _result?.correct ?? false;
    final reward = _reward;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC000000),
        child: Center(
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
            decoration: BoxDecoration(
              color: const Color(0xF21F1B15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: correct ? const Color(0xFFD4A843) : Colors.white24,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: correct
                      ? const Color(0xFF6BCB6B)
                      : const Color(0xFFFF6B5E),
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(
                  correct ? '答對了！' : '答錯了',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 14),
                if (correct && reward != null) ...[
                  const Text('獲得原料',
                      style: TextStyle(color: Colors.white60, fontSize: 14)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: FramedComponentTile(component: reward),
                  ),
                  const SizedBox(height: 8),
                  Text('${reward.name}　Lv.${reward.level}',
                      style: const TextStyle(
                        color: Color(0xFFE8DCC0),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      )),
                ] else if (correct) ...[
                  const Text('（此難度暫無可獲得的原料）',
                      style: TextStyle(color: Colors.white60, fontSize: 14)),
                ] else
                  const Text('再接再厲，換下一題試試！',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: _nextRound,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 44, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A843),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Text('下一題',
                        style: TextStyle(
                          color: Color(0xFF2A1A0A),
                          fontSize: 18,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeUpOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icons/times_up.png',
                  width: 280, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              const SizedBox(height: 8),
              const Text('資源採集結束',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _timeUpButton(
                    label: '返回我的古蹟',
                    filled: false,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 18),
                  _timeUpButton(
                    label: '前往編輯',
                    filled: true,
                    onTap: () => context.pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeUpButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFD4A843) : const Color(0xCC241F19),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: filled ? const Color(0xFFD4A843) : Colors.white38,
            width: 1.4,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: filled ? const Color(0xFF2A1A0A) : Colors.white,
              fontSize: 17,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

// ── 原料採集關卡卡片 ────────────────────────────────────────────────────────────
class _DifficultyCard extends StatelessWidget {
  final String name;
  final String imagePath;
  final int stars;
  final String progress;
  final VoidCallback onTap;

  const _DifficultyCard({
    required this.name,
    required this.imagePath,
    required this.stars,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: const Color(0xFFCDB590),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF8A6A40), width: 1.5),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 14, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              // 進度條（已採集 / 總數）。
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                color: const Color(0xF0241F19),
                alignment: Alignment.center,
                child: Text(progress,
                    style: const TextStyle(
                      color: Color(0xFFE8DCC0),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    )),
              ),
              const SizedBox(height: 14),
              Text(name,
                  style: const TextStyle(
                    color: Color(0xFF2A1A0A),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  )),
              const SizedBox(height: 8),
              Expanded(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 區域圖：底部多留白，讓星數可貼著下緣並稍微重疊其上。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: Color(0x55000000),
                          size: 60,
                        ),
                      ),
                    ),
                    // 星數：放大並貼在區域圖下方、稍微重疊其下緣。
                    Positioned(
                      bottom: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < stars; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Image.asset(
                                'assets/icons/star.png',
                                width: 42,
                                height: 42,
                                errorBuilder: (_, _, _) => const Icon(
                                    Icons.star,
                                    color: Color(0xFFD4A843),
                                    size: 42),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 選擇題選項 ───────────────────────────────────────────────────────────────
class _ChoiceTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  const _ChoiceTile({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF241F19),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? const Color(0xFFD4A843) : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFD4A843)
                    : const Color(0x33FFFFFF),
                shape: BoxShape.circle,
              ),
              child: Text('${index + 1}',
                  style: TextStyle(
                    color: selected ? const Color(0xFF2A1A0A) : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  )),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                    color: Color(0xFFF0E8D8),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 麥克風按鈕 ───────────────────────────────────────────────────────────────
class _MicButton extends StatelessWidget {
  final bool recording;
  const _MicButton({required this.recording});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: recording ? 96 : 86,
      height: recording ? 96 : 86,
      decoration: BoxDecoration(
        color: recording ? const Color(0xFFFF6B5E) : const Color(0xFF241F19),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD4A843), width: 2),
        boxShadow: [
          if (recording)
            const BoxShadow(
                color: Color(0x66FF6B5E), blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Icon(
        recording ? Icons.mic : Icons.mic_none_rounded,
        color: recording ? Colors.white : const Color(0xFFD4A843),
        size: 40,
      ),
    );
  }
}
