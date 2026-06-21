import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';
import 'game_state_service.dart';

/// [GameStateService] 的後端實作：
///   - [fetch] ↔ `GET /api/state` → `{ "state": "...", "updated_at": "..." }`
///   - [watch] ↔ `GET /api/state/ws`（連線即收一份當前狀態，之後每次老師端切換即推播）
///
/// 後端提供「目前階段 + 開始時間（updated_at）+ 排程結束時間（end_time，可選）」。
/// 有 end_time 時倒數以它為準（= 老師設定的結束時刻，跨裝置同步、到時後端自動回
/// NORMAL）；沒有 end_time（如老師未設時長）時退回前端各階段固定長度 [_phaseDuration]。
/// 階段對應：NORMAL=平時、QUIZ1=資源採集、QUIZ2=攻防戰。
class ApiGameStateService implements GameStateService {
  ApiGameStateService(this._client);

  final ApiClient _client;

  /// 後端未帶 end_time 時的後備倒數長度（依階段）。
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
    // 後端排程的結束時刻（RFC3339）→ 以「結束 − 開始」當倒數長度（snapshot.endTime 即等於
    // end_time，跨裝置同步）；無 end_time 則用各階段固定後備長度。
    final endRaw = m['end_time'] as String?;
    final end = endRaw != null ? DateTime.tryParse(endRaw)?.toLocal() : null;
    Duration duration;
    if (end != null) {
      duration = end.difference(started);
      if (duration.isNegative) duration = Duration.zero;
    } else {
      duration = _phaseDuration[phase] ?? Duration.zero;
    }
    return GameStateSnapshot(
      phase: phase,
      startTime: started,
      duration: duration,
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
      // 共用 ApiClient 的 HttpClient，沿用其自簽憑證放行，wss:// 自簽後端才連得上。
      final ws = await WebSocket.connect(wsUrl, customClient: _client.httpClient);
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
            // 同一條 WS 也會推攻防戰的 `slot_update` 幀（`{type:"slot_update",user_id}`，
            // 由 [FightService] 處理）。狀態幀無 `type` 欄位；非狀態幀一律略過，
            // 否則會被當成缺 state → 誤判成 NORMAL，害遊戲階段亂跳。
            if (m['type'] != null || m['state'] == null) return;
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
