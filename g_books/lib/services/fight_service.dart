import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../data/component_data.dart' show componentsOf, componentById;
import '../data/slot_data.dart' show slotsOf;
import 'api_client.dart';

/// 攻防戰（QUIZ2）資料來源抽象層。Mock 與 Api 雙實作，後端對接點全部預留。
///
/// 對應後端（見專案根 `後端功能.md`）：
///   - [fetchAllGroups]   ↔ G2 彙整端點；無則 `GET /api/users` + 各組 `POST /api/item`（N+1）
///   - [watchEvents]      ↔ G1 戰況 WS 事件（被打 / 修復）；後端未備妥前回空串流
///   - [fetchLeaderboard] ↔ G3 排行榜端點；無則由全體狀態自算
///
/// 血量（G3）：上限 = 該組所有已放置元件難度分(level 1~3)加總；
/// 剩餘 = 其中未損毀者加總。元件難度來自 building layout（前端 [componentById] 的 level）。

/// 一格已放置元件在攻防戰中的狀態。
class FightSlot {
  /// slot 幾何 id（對應 [slotsOf] 的 [HeritageSlot.id]）。
  final int slotId;

  /// 元件 id（= 後端 item type / 前端 component id）。
  final int type;

  /// 已被打壞。
  final bool broken;

  /// 對「目前這組（caller）」而言，這格因先前答錯而禁止再攻擊（後端 G4）。
  final bool attackBlocked;

  const FightSlot({
    required this.slotId,
    required this.type,
    this.broken = false,
    this.attackBlocked = false,
  });

  FightSlot copyWith({bool? broken, bool? attackBlocked}) => FightSlot(
        slotId: slotId,
        type: type,
        broken: broken ?? this.broken,
        attackBlocked: attackBlocked ?? this.attackBlocked,
      );
}

/// 一組在攻防戰中的整體狀態（含血量與各格元件）。
class FightGroup {
  final int userId;
  final String displayName;
  final String? avatarUrl;
  final int buildingId;

  /// slot_id → 該格元件狀態。
  final Map<int, FightSlot> slots;

  const FightGroup({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.buildingId = 0,
    this.slots = const {},
  });

  /// 上限血量 = 所有已放置元件難度分加總。
  int hpMax(String heritageId) => _score(heritageId, (s) => true);

  /// 剩餘血量 = 未損毀元件難度分加總。
  int hp(String heritageId) => _score(heritageId, (s) => !s.broken);

  int _score(String heritageId, bool Function(FightSlot) keep) {
    var sum = 0;
    for (final s in slots.values) {
      if (!keep(s)) continue;
      sum += componentById(heritageId, s.type)?.level ?? 1;
    }
    return sum;
  }

  /// 未損毀的已放置格（自己島嶼「剩餘元件」/ 敵島可攻擊判斷用）。
  Iterable<FightSlot> get intactSlots => slots.values.where((s) => !s.broken);

  /// 已損毀的格（自己島嶼「損毀元件」/ 補給站修復清單用）。
  Iterable<FightSlot> get brokenSlots => slots.values.where((s) => s.broken);

  FightGroup copyWithSlots(Map<int, FightSlot> next) => FightGroup(
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        buildingId: buildingId,
        slots: next,
      );
}

/// 戰況事件種類。
/// 戰況事件：對應後端 WS 的 `slot_update` 幀 `{ "type":"slot_update", "user_id": N }`。
/// 後端只告知「哪位使用者的 slot 有變動」（移動 / 攻擊 / 修復皆會推），收到後前端
/// refetch 該組（或全體）狀態以更新地圖。
///
/// ⚠️ 後端**未**提供「攻擊者是誰 / 打了哪格 / 哪個元件」。故 App 內被攻擊通知（需求 4）
/// 只能由前端比對自己組的前後快照推出「我方某元件被攻破」，**無法得知是哪一組攻擊**。
class FightEvent {
  /// slot 有變動的使用者（= slot_update 的 user_id）。
  final int userId;
  const FightEvent(this.userId);
}

/// 排行榜一列（對接 G3）。
class LeaderboardEntry {
  final int rank;
  final int userId;
  final String displayName;
  final String? avatarUrl;
  final int hp;
  final int hpMax;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.hp,
    required this.hpMax,
  });
}

abstract class FightService {
  /// 取得所有參戰組（含自己）的當前狀態。[selfUserId] 用來在 Mock 標出自己這組、
  /// 在 Api 判斷 attackBlocked 視角；[heritageId] 供難度/元件查詢。
  Future<List<FightGroup>> fetchAllGroups({
    required int selfUserId,
    required String heritageId,
  });

  /// 訂閱戰況事件（被打 / 修復）。收到後畫面應 refetch 全體狀態並更新地圖。
  Stream<FightEvent> watchEvents();

  /// 時間到取得排行榜結果。
  Future<List<LeaderboardEntry>> fetchLeaderboard({
    required int selfUserId,
    required String heritageId,
  });

  /// 本機套用一次攻擊 / 修復結果（把某組某格設為 [broken]）：Mock 用以同步世界地圖
  /// 並推播 slot_update；Api 版為 no-op（真實狀態改變由後端完成，靠 refetch + WS 反映）。
  Future<void> localApply({
    required int targetUserId,
    required int slotId,
    required bool broken,
  }) async {}

  void dispose() {}
}

/// 由各組狀態算排行榜（Api 後端無排行榜端點時、與 Mock 共用的後備計算）。
List<LeaderboardEntry> rankGroups(List<FightGroup> groups, String heritageId) {
  final sorted = [...groups]
    ..sort((a, b) => b.hp(heritageId).compareTo(a.hp(heritageId)));
  return [
    for (var i = 0; i < sorted.length; i++)
      LeaderboardEntry(
        rank: i + 1,
        userId: sorted[i].userId,
        displayName: sorted[i].displayName,
        avatarUrl: sorted[i].avatarUrl,
        hp: sorted[i].hp(heritageId),
        hpMax: sorted[i].hpMax(heritageId),
      ),
  ];
}

/// 本機 mock：以真實古蹟的 slot 幾何與元件隨機生成數組敵方，加上自己這組，
/// 供離線開發整套攻防戰 UI。[watchEvents] 定時模擬有人被打 / 被修，畫面即時更新。
class MockFightService implements FightService {
  MockFightService({this.enemyCount = 5});

  /// 生成的敵方組數（連同自己共 enemyCount+1 組，務必 < 16）。
  final int enemyCount;

  final _rng = Random(7);
  final _ctrl = StreamController<FightEvent>.broadcast();
  Timer? _timer;

  /// 生成一次後快取（watchEvents 會就地變更，fetchAllGroups 回最新）。
  List<FightGroup>? _cache;
  String _heritageId = '';

  static const _enemyNames = [
    '胖仔大砲蛙隊',
    '野仔大樹蛙隊',
    '雷公電火蛙隊',
    '飛天小金剛隊',
    '無敵鐵金龜隊',
    '海角樂團蛙隊',
    '閃電泥鰍隊',
  ];

  List<FightGroup> _generate(int selfUserId, String heritageId) {
    final slots = slotsOf(heritageId);
    final comps = componentsOf(heritageId);
    FightGroup makeGroup(int id, String name, {required bool isSelf}) {
      final filled = <int, FightSlot>{};
      for (final s in slots) {
        // 自己組填多一點、敵方稀疏些，營造不同戰況。
        final fillChance = isSelf ? 0.8 : 0.55;
        if (_rng.nextDouble() > fillChance) continue;
        // 找可放這格的元件；沒有就略過。
        final allowed = [for (final c in comps) if (c.canPlaceIn(s.id)) c];
        if (allowed.isEmpty) continue;
        final c = allowed[_rng.nextInt(allowed.length)];
        final broken = !isSelf ? false : false; // 初始皆未損毀，靠事件演進
        filled[s.id] = FightSlot(slotId: s.id, type: c.id, broken: broken);
      }
      return FightGroup(
        userId: id,
        displayName: name,
        avatarUrl: null,
        buildingId: 1,
        slots: filled,
      );
    }

    return [
      makeGroup(selfUserId, '我方小隊', isSelf: true),
      for (var i = 0; i < enemyCount; i++)
        makeGroup(9001 + i, _enemyNames[i % _enemyNames.length], isSelf: false),
    ];
  }

  List<FightGroup> _ensure(int selfUserId, String heritageId) {
    if (_cache == null || _heritageId != heritageId) {
      _heritageId = heritageId;
      _cache = _generate(selfUserId, heritageId);
    }
    return _cache!;
  }

  @override
  Future<List<FightGroup>> fetchAllGroups({
    required int selfUserId,
    required String heritageId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return [..._ensure(selfUserId, heritageId)];
  }

  @override
  Stream<FightEvent> watchEvents() {
    _timer ??= Timer.periodic(const Duration(seconds: 6), (_) => _tick());
    return _ctrl.stream;
  }

  /// 隨機挑一組未損毀的格打壞，推播事件。純供 Mock 演進世界地圖。
  void _tick() {
    final cache = _cache;
    if (cache == null || _ctrl.isClosed) return;
    final candidates = <(int, FightSlot)>[];
    for (var gi = 0; gi < cache.length; gi++) {
      for (final s in cache[gi].slots.values) {
        if (!s.broken) candidates.add((gi, s));
      }
    }
    if (candidates.isEmpty) return;
    final (gi, slot) = candidates[_rng.nextInt(candidates.length)];
    final target = cache[gi];
    final next = Map<int, FightSlot>.from(target.slots)
      ..[slot.slotId] = slot.copyWith(broken: true);
    cache[gi] = target.copyWithSlots(next);
    // 仿後端 slot_update：只通知「該組 slot 有變動」，前端 refetch。
    _ctrl.add(FightEvent(target.userId));
  }

  @override
  Future<void> localApply({
    required int targetUserId,
    required int slotId,
    required bool broken,
  }) async {
    final cache = _cache;
    if (cache == null) return;
    final gi = cache.indexWhere((g) => g.userId == targetUserId);
    if (gi < 0) return;
    final slot = cache[gi].slots[slotId];
    if (slot == null) return;
    final next = Map<int, FightSlot>.from(cache[gi].slots)
      ..[slotId] = slot.copyWith(broken: broken);
    cache[gi] = cache[gi].copyWithSlots(next);
    if (!_ctrl.isClosed) _ctrl.add(FightEvent(targetUserId));
  }

  @override
  Future<List<LeaderboardEntry>> fetchLeaderboard({
    required int selfUserId,
    required String heritageId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return rankGroups(_ensure(selfUserId, heritageId), heritageId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }
}

/// 後端實作。目前以現有端點盡力拼出全體狀態；G1/G2/G3 缺口處清楚標註「預留」。
class ApiFightService implements FightService {
  ApiFightService(this._client);

  final ApiClient _client;

  // 攻防戰 slot_update WS（與 ApiGameStateService 各自連線到同一 /api/state/ws；
  // 兩者用 `type` 欄位各取所需：本服務只處理 slot_update，狀態幀略過）。
  StreamController<FightEvent>? _ctrl;
  WebSocket? _ws;
  bool _connecting = false;
  bool _closed = false;

  @override
  Future<List<FightGroup>> fetchAllGroups({
    required int selfUserId,
    required String heritageId,
  }) async {
    // 預留 G2：理想是一支彙整端點。未備妥前用 GET /api/users + 各組 POST /api/item。
    final usersResp =
        await _client.getJson('/api/users') as Map<String, dynamic>;
    final users = (usersResp['users'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        // 只取小組帳號（role=0）。
        .where((u) => ((u['role'] as num?)?.toInt() ?? -1) == 0)
        .toList();

    final groups = <FightGroup>[];
    for (final u in users) {
      final uid = (u['id'] as num?)?.toInt() ?? 0;
      if (uid == 0) continue;
      final slots = await _fetchSlots(uid, selfUserId);
      groups.add(FightGroup(
        userId: uid,
        displayName: ((u['display_name'] as String?)?.trim().isNotEmpty ?? false)
            ? (u['display_name'] as String)
            : (u['username'] as String? ?? ''),
        avatarUrl: () {
          final p = (u['profile_pic_url'] as String?) ?? '';
          return p.isEmpty ? null : p;
        }(),
        buildingId: (u['building_id'] as num?)?.toInt() ?? 0,
        slots: slots,
      ));
    }
    return groups;
  }

  /// 取某組的 slot 狀態（type + broken + 對 [selfUserId] 而言是否被禁打）。
  /// 學生查別組為受限視圖（無 item_id/question_id），但 `blocked_attackers` 兩種視圖都會回。
  Future<Map<int, FightSlot>> _fetchSlots(int userId, int selfUserId) async {
    try {
      final m = await _client.sendJson('POST', '/api/item',
          body: {'user_id': userId}) as Map<String, dynamic>;
      final out = <int, FightSlot>{};
      final rawSlots = m['slots'] as Map<String, dynamic>? ?? const {};
      rawSlots.forEach((k, v) {
        final mm = v as Map<String, dynamic>;
        final slotId = int.tryParse(k) ?? -1;
        if (slotId < 0) return;
        // blocked_attackers：被禁止攻擊這格的 user_id 清單（空時後端省略）。
        // 對「我」而言被禁打 = 清單含 selfUserId（G4）。
        final blocked = (mm['blocked_attackers'] as List? ?? const [])
            .map((x) => (x as num).toInt());
        out[slotId] = FightSlot(
          slotId: slotId,
          type: (mm['type'] as num?)?.toInt() ?? 0,
          broken: mm['broken'] == true,
          attackBlocked: blocked.contains(selfUserId),
        );
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  Stream<FightEvent> watchEvents() {
    _ctrl ??= StreamController<FightEvent>.broadcast(onListen: _connect);
    return _ctrl!.stream;
  }

  // 連線 /api/state/ws，只取 `slot_update` 幀 → 推出 FightEvent(user_id)。
  // 寫法比照 [ApiGameStateService]（共用 ApiClient 的自簽憑證 HttpClient、斷線重連）。
  Future<void> _connect() async {
    if (_closed || _connecting || _ws != null) return;
    final token = _client.accessToken;
    if (token == null) return;
    _connecting = true;
    final wsUrl = '${_client.baseUrl.replaceFirst('http', 'ws')}/api/state/ws'
        '?access_token=${Uri.encodeQueryComponent(token)}';
    try {
      final ws =
          await WebSocket.connect(wsUrl, customClient: _client.httpClient);
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
            // 只處理攻防戰的 slot_update；狀態幀交給 ApiGameStateService。
            if (m['type'] != 'slot_update') return;
            final uid = (m['user_id'] as num?)?.toInt();
            if (uid != null) _ctrl?.add(FightEvent(uid));
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
    if (_ctrl == null || !_ctrl!.hasListener) return;
    Future<void>.delayed(const Duration(seconds: 3), _connect);
  }

  @override
  Future<List<LeaderboardEntry>> fetchLeaderboard({
    required int selfUserId,
    required String heritageId,
  }) async {
    // G3：後端 GET /api/scores 回 `{scores:[{user_id, score}]}`（QUIZ2 結束時重算，
    // score = 未損毀 slot 元件的題目難度加總 = 剩餘血量）。端點只給分數，故合併
    // GET /api/users 補 display_name / 頭像，名次由前端排（需求 3 僅需剩餘血量）。
    try {
      final scoresResp =
          await _client.getJson('/api/scores') as Map<String, dynamic>;
      final rows = (scoresResp['scores'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        // 首次 QUIZ2 尚未結束 → 後備：用目前全體狀態自算。
        final groups =
            await fetchAllGroups(selfUserId: selfUserId, heritageId: heritageId);
        return rankGroups(groups, heritageId);
      }
      final meta = <int, ({String name, String? avatar, int role})>{};
      try {
        final usersResp =
            await _client.getJson('/api/users') as Map<String, dynamic>;
        for (final u in (usersResp['users'] as List? ?? const [])
            .cast<Map<String, dynamic>>()) {
          final id = (u['id'] as num?)?.toInt() ?? 0;
          final p = (u['profile_pic_url'] as String?) ?? '';
          meta[id] = (
            name: ((u['display_name'] as String?)?.trim().isNotEmpty ?? false)
                ? u['display_name'] as String
                : (u['username'] as String? ?? ''),
            avatar: p.isEmpty ? null : p,
            role: (u['role'] as num?)?.toInt() ?? -1,
          );
        }
      } catch (_) {}
      final ranked = [
        for (final r in rows)
          (
            userId: (r['user_id'] as num?)?.toInt() ?? 0,
            score: (r['score'] as num?)?.toInt() ?? 0,
          ),
      ]
        // 只留小組帳號（meta 找不到的保險起見也保留）。
        ..removeWhere((e) => meta[e.userId] != null && meta[e.userId]!.role != 0)
        ..sort((a, b) => b.score.compareTo(a.score));
      return [
        for (var i = 0; i < ranked.length; i++)
          LeaderboardEntry(
            rank: i + 1,
            userId: ranked[i].userId,
            displayName: meta[ranked[i].userId]?.name ?? '',
            avatarUrl: meta[ranked[i].userId]?.avatar,
            hp: ranked[i].score,
            hpMax: 0, // 後端只給剩餘分數，無上限。
          ),
      ];
    } catch (_) {
      final groups =
          await fetchAllGroups(selfUserId: selfUserId, heritageId: heritageId);
      return rankGroups(groups, heritageId);
    }
  }

  @override
  Future<void> localApply({
    required int targetUserId,
    required int slotId,
    required bool broken,
  }) async {
    // Api 版 no-op：真實狀態改變由後端完成，前端靠 refetch + WS slot_update 反映。
  }

  @override
  void dispose() {
    _closed = true;
    _ws?.close();
    _ws = null;
    _ctrl?.close();
  }
}
