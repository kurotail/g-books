import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 遊戲階段：由老師端切換，前端進入檢視古蹟時取得、並透過 websocket 即時更新。
/// - [normal]：一般檢視（採集 / 攻防戰皆未開放）
/// - [quiz1]：資源採集
/// - [quiz2]：攻防戰
enum GamePhase { normal, quiz1, quiz2 }

/// 某一刻的遊戲狀態快照：目前階段 + 該階段開始時間 + 預定持續長度。
/// 倒數 = startTime + duration − now（持續長度先由（假）後端提供，之後可改為後端
/// 直接回結束時間）。
class GameStateSnapshot {
  final GamePhase phase;
  final DateTime startTime;
  final Duration duration;

  const GameStateSnapshot({
    required this.phase,
    required this.startTime,
    required this.duration,
  });

  DateTime get endTime => startTime.add(duration);

  /// 距結束的剩餘時間（不為負）。
  Duration remaining(DateTime now) {
    final r = endTime.difference(now);
    return r.isNegative ? Duration.zero : r;
  }

  bool get isQuiz => phase == GamePhase.quiz1 || phase == GamePhase.quiz2;
}

/// 遊戲狀態來源抽象層。對應後端：
///   - [fetch] ↔ 進入檢視古蹟時取得目前階段 + 開始時間
///   - [watch] ↔ 老師端 websocket 推播的階段變更（連線即送一份目前快照）
///
/// 之後換真後端只要新增 `ApiGameStateService implements GameStateService`，
/// 在 `main.dart` 換掉實作，前端與 UI 不需更動。
abstract class GameStateService {
  Future<GameStateSnapshot> fetch();
  Stream<GameStateSnapshot> watch();
  void dispose() {}
}

/// 本機 mock：預設停在 [GamePhase.quiz1]（資源採集）、持續 3 分鐘，方便開發測試。
///
/// 為了能驗證「中途跳出 App、重啟後接續同場次」，[init] 會把目前場次（階段 + 開始
/// 時間 + 長度）持久化到本機，重啟後若同場次尚未結束則沿用同一開始時間（模擬後端的
/// 場次不因 App 重啟而改變）；場次已結束才開新場次。[pushPhase] 模擬老師端切換階段。
class MockGameStateService implements GameStateService {
  MockGameStateService({
    this.defaultPhase = GamePhase.quiz1,
    this.defaultDuration = const Duration(minutes: 3),
  })  : _phase = defaultPhase,
        _duration = defaultDuration,
        _startTime = DateTime.now();

  final GamePhase defaultPhase;
  final Duration defaultDuration;

  GamePhase _phase;
  Duration _duration;
  DateTime _startTime;
  final _ctrl = StreamController<GameStateSnapshot>.broadcast();

  GameStateSnapshot get _snapshot => GameStateSnapshot(
        phase: _phase,
        startTime: _startTime,
        duration: _duration,
      );

  /// 啟動時還原 / 建立場次。沿用尚未結束的場次（開始時間不變）以便接續進度。
  Future<void> init() async {
    final saved = await _loadSession();
    final now = DateTime.now();
    if (saved != null && saved.endTime.isAfter(now)) {
      _phase = saved.phase;
      _duration = saved.duration;
      _startTime = saved.startTime;
    } else {
      _phase = defaultPhase;
      _duration = defaultDuration;
      _startTime = now;
      await _saveSession();
    }
  }

  @override
  Future<GameStateSnapshot> fetch() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _snapshot;
  }

  @override
  Stream<GameStateSnapshot> watch() {
    // 連線即送一份目前快照（仿 WS on-connect snapshot）。
    scheduleMicrotask(() {
      if (!_ctrl.isClosed) _ctrl.add(_snapshot);
    });
    return _ctrl.stream;
  }

  /// （測試輔助）模擬老師端切換階段：重設開始時間、持久化並推播給所有訂閱者。
  void pushPhase(GamePhase phase, {Duration? duration}) {
    _phase = phase;
    if (duration != null) _duration = duration;
    _startTime = DateTime.now();
    _saveSession();
    if (!_ctrl.isClosed) _ctrl.add(_snapshot);
  }

  // ── 場次持久化（模擬後端：重啟後同場次開始時間不變）──────────────────────────
  Future<File> _sessionFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gb_game_session.json');
  }

  Future<GameStateSnapshot?> _loadSession() async {
    try {
      final f = await _sessionFile();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return GameStateSnapshot(
        phase: GamePhase.values.byName(m['phase'] as String),
        startTime: DateTime.parse(m['startTime'] as String),
        duration: Duration(milliseconds: (m['durationMs'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession() async {
    try {
      final f = await _sessionFile();
      await f.writeAsString(jsonEncode({
        'phase': _phase.name,
        'startTime': _startTime.toIso8601String(),
        'durationMs': _duration.inMilliseconds,
      }));
    } catch (_) {}
  }

  @override
  void dispose() => _ctrl.close();
}
