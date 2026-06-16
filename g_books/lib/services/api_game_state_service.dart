import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';
import 'game_state_service.dart';

/// [GameStateService] 的後端實作：
///   - [fetch] ↔ `GET /api/state` → `{ "state": "...", "updated_at": "..." }`
///   - [watch] ↔ `GET /api/state/ws`（連線即收一份當前狀態，之後每次老師端切換即推播）
///
/// 後端只提供「目前階段 + 該階段開始時間（updated_at）」，**沒有持續長度**；倒數長度
/// 由前端依階段給固定值（[_phaseDuration]），倒數 = updated_at + duration − now。
/// 階段對應：NORMAL=平時、QUIZ1=資源採集、QUIZ2=攻防戰。
class ApiGameStateService implements GameStateService {
  ApiGameStateService(this._client);

  final ApiClient _client;

  /// 各階段倒數長度（後端只給開始時間，這裡補上長度）。
  static const Map<GamePhase, Duration> _phaseDuration = {
    GamePhase.normal: Duration.zero,
    GamePhase.quiz1: Duration(minutes: 3), // 資源採集
    GamePhase.quiz2: Duration(minutes: 3), // 攻防戰（暫定）
  };

  StreamController<GameStateSnapshot>? _ctrl;
  WebSocket? _ws;
  bool _connecting = false;
  bool _closed = false;

  @override
  Future<GameStateSnapshot> fetch() async {
    final m = await _client.getJson('/api/state') as Map<String, dynamic>;
    return _parse(m);
  }

  @override
  Stream<GameStateSnapshot> watch() {
    _ctrl ??= StreamController<GameStateSnapshot>.broadcast(onListen: _connect);
    return _ctrl!.stream;
  }

  GameStateSnapshot _parse(Map<String, dynamic> m) {
    final phase = _phaseFromName(m['state'] as String?);
    final raw = m['updated_at'] as String?;
    final started =
        (raw != null ? DateTime.tryParse(raw) : null)?.toLocal() ?? DateTime.now();
    return GameStateSnapshot(
      phase: phase,
      startTime: started,
      duration: _phaseDuration[phase] ?? Duration.zero,
    );
  }

  static GamePhase _phaseFromName(String? s) => switch (s) {
        'QUIZ1' => GamePhase.quiz1,
        'QUIZ2' => GamePhase.quiz2,
        _ => GamePhase.normal,
      };

  // ── WebSocket：連線 / 推播 / 斷線重連 ─────────────────────────────────────────
  Future<void> _connect() async {
    if (_closed || _connecting || _ws != null) return;
    final token = _client.accessToken;
    if (token == null) return; // 尚未登入；登入後 watch 的下一位訂閱者會觸發連線
    _connecting = true;
    // http(s):// → ws(s)://，帶 access_token query（瀏覽器外也可用 header，這裡用 query 較單純）。
    final wsUrl =
        '${_client.baseUrl.replaceFirst('http', 'ws')}/api/state/ws'
        '?access_token=${Uri.encodeQueryComponent(token)}';
    try {
      final ws = await WebSocket.connect(wsUrl);
      _connecting = false;
      if (_closed) {
        await ws.close();
        return;
      }
      _ws = ws;
      ws.listen(
        (data) {
          try {
            final m = jsonDecode(data as String) as Map<String, dynamic>;
            _ctrl?.add(_parse(m));
          } catch (_) {/* 略過壞幀 */}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _ws = null;
    if (_closed) return;
    // 沒有訂閱者就不重連，待下次 watch 訂閱時再由 onListen 觸發。
    if (_ctrl == null || !_ctrl!.hasListener) return;
    Future<void>.delayed(const Duration(seconds: 3), _connect);
  }

  @override
  void dispose() {
    _closed = true;
    _ws?.close();
    _ws = null;
    _ctrl?.close();
  }
}
