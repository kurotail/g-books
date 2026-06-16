import 'dart:async';
import 'api_client.dart';

/// 學生對「非自己組別」操作物品時，後端回 403。多半是老師把這位學生換了組、但他
/// 還沒重登（App 仍持舊 group_id）。UI 收到此例外應提示「分組已變更，請重新登入」。
class GroupChangedException implements Exception {
  const GroupChangedException();
}

/// 一個背包物品實例（對應後端 item）。
/// - [itemId]：唯一實例 id（後端 inv2slot/slot2inv 以此辨識；同種類可有多個實例）
/// - [type]  ：物品種類 = 前端的「原料 id（component id）」
/// - [questionId]：連結的題目 id（0 = 無）
class OwnedItem {
  final int itemId;
  final int type;
  final int questionId;
  const OwnedItem({required this.itemId, required this.type, this.questionId = 0});
}

/// slot 上的物品：同 [OwnedItem]，再加是否 [broken]（攻防戰被打壞）。
class SlotItem {
  final int itemId;
  final int type;
  final int questionId;
  final bool broken;
  const SlotItem({
    required this.itemId,
    required this.type,
    this.questionId = 0,
    this.broken = false,
  });
}

/// 某組的背包 + 放置狀態快照（形狀對齊後端 `POST /api/item`：
/// `inventory` 為實例清單、`slots` 為 `slot_id → 物品`）。
class HeritageBoardSnapshot {
  /// 散裝（未放置）的物品實例。
  final List<OwnedItem> inventory;

  /// 已放置：slot_id → 物品。
  final Map<int, SlotItem> slots;

  const HeritageBoardSnapshot({required this.inventory, required this.slots});

  HeritageBoardSnapshot copy() => HeritageBoardSnapshot(
        inventory: List<OwnedItem>.from(inventory),
        slots: Map<int, SlotItem>.from(slots),
      );
}

/// 編輯古蹟 / 我的古蹟的資料來源抽象層。對應後端 `gb_api`：
///   - [fetchItems] ↔ `POST /api/item`
///   - [placeItem]  ↔ `POST /api/item/inv2slot`
///   - [removeItem] ↔ `POST /api/item/slot2inv`
///   - [watch]      ↔ 後端目前只有狀態 WS、無背包推播，故 API 實作回空串流；
///                    本機 mock 於變動時推播以模擬多裝置同步。
///
/// ⚠️ 後端 inv2slot **會**驗證「此 type 是否可放此 slot」（依該組 building 的
/// `item_allowed_slot`）。前端也以 [ComponentModel.allowedSlotIds] 同步驗證，兩者需一致。
abstract class HeritageSyncService {
  Future<HeritageBoardSnapshot> fetchItems(int groupId);

  /// 把背包中的 [itemId]（實例）放進 [slotId]。成功回 true。
  Future<bool> placeItem({
    required int groupId,
    required int itemId,
    required int slotId,
  });

  /// 把 [slotId] 上的物品收回背包。成功回 true。
  Future<bool> removeItem({required int groupId, required int slotId});

  /// 發一個 [type] 種類的新實例到背包（採集獎勵）。回新實例 itemId、失敗回 null。
  ///
  /// 後端真正的採集獎勵是「答對題目後由伺服器入庫」（見 quiz answer 回的 item_id），
  /// 故此法僅供本機 mock；[ApiHeritageSyncService] 不支援。
  Future<int?> grantItem({required int groupId, required int type});

  /// 訂閱該組的即時變動（其他裝置 / 攻防戰造成）。
  Stream<HeritageBoardSnapshot> watch(int groupId);

  void dispose() {}
}

/// 本機 mock：以記憶體保存各組的物品實例（背包 + slot），行為比照後端
/// （inv2slot 換出原本正常物品、損毀不可替換 / 收回）。變動後即時 [watch] 推播。
/// 資料形狀與 [ApiHeritageSyncService] 一致，之後切換只是換傳輸、UI 不需更動。
class MockHeritageSyncService implements HeritageSyncService {
  final Map<int, List<OwnedItem>> _inventory = {}; // groupId → 散裝實例
  final Map<int, Map<int, SlotItem>> _slots = {}; // groupId → slotId → 物品
  final Map<int, StreamController<HeritageBoardSnapshot>> _controllers = {};
  int _nextItemId = 1000; // 比照後端：高基底避免與種子 id 撞號

  /// 預設背包：各 type（原料 id）給幾個實例，方便開發測試。
  static const Map<int, int> _seedCounts = {
    1: 2, 2: 1, 3: 3, 4: 1, // lv1
    5: 1, 6: 1, 7: 2, // lv2
    9: 1, 11: 1, // lv3
  };

  List<OwnedItem> _inv(int g) => _inventory.putIfAbsent(g, () {
        final list = <OwnedItem>[];
        _seedCounts.forEach((type, n) {
          for (var i = 0; i < n; i++) {
            list.add(OwnedItem(itemId: _nextItemId++, type: type));
          }
        });
        return list;
      });

  Map<int, SlotItem> _slt(int g) => _slots.putIfAbsent(g, () => <int, SlotItem>{});

  StreamController<HeritageBoardSnapshot> _ctrl(int g) =>
      _controllers.putIfAbsent(
        g,
        () => StreamController<HeritageBoardSnapshot>.broadcast(),
      );

  HeritageBoardSnapshot _snapshot(int g) => HeritageBoardSnapshot(
        inventory: List<OwnedItem>.from(_inv(g)),
        slots: Map<int, SlotItem>.from(_slt(g)),
      );

  void _emit(int g) {
    if (_controllers.containsKey(g)) _ctrl(g).add(_snapshot(g));
  }

  @override
  Future<HeritageBoardSnapshot> fetchItems(int groupId) async =>
      _snapshot(groupId);

  @override
  Future<bool> placeItem({
    required int groupId,
    required int itemId,
    required int slotId,
  }) async {
    final inv = _inv(groupId);
    final idx = inv.indexWhere((it) => it.itemId == itemId);
    if (idx < 0) return false; // 不在背包
    final slots = _slt(groupId);
    final existing = slots[slotId];
    if (existing != null && existing.broken) return false; // 損毀不可替換
    final item = inv.removeAt(idx);
    if (existing != null) {
      // 原本的正常物品換回背包
      inv.add(OwnedItem(
        itemId: existing.itemId,
        type: existing.type,
        questionId: existing.questionId,
      ));
    }
    slots[slotId] = SlotItem(
      itemId: item.itemId,
      type: item.type,
      questionId: item.questionId,
    );
    _emit(groupId);
    return true;
  }

  @override
  Future<bool> removeItem({required int groupId, required int slotId}) async {
    final slots = _slt(groupId);
    final it = slots[slotId];
    if (it == null || it.broken) return false; // 空或損毀不可收回
    slots.remove(slotId);
    _inv(groupId).add(OwnedItem(
      itemId: it.itemId,
      type: it.type,
      questionId: it.questionId,
    ));
    _emit(groupId);
    return true;
  }

  @override
  Future<int?> grantItem({required int groupId, required int type}) async {
    final id = _nextItemId++;
    _inv(groupId).add(OwnedItem(itemId: id, type: type));
    _emit(groupId);
    return id;
  }

  @override
  Stream<HeritageBoardSnapshot> watch(int groupId) {
    final ctrl = _ctrl(groupId);
    // 連線即送一份目前快照（仿 WS on-connect snapshot）。
    scheduleMicrotask(() {
      if (!ctrl.isClosed) ctrl.add(_snapshot(groupId));
    });
    return ctrl.stream;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }
}

/// 後端實作：背包 / 放置走 `POST /api/item`、`/inv2slot`、`/slot2inv`。
/// 後端無背包推播（只有狀態 WS），[watch] 回空串流；變動後由 controller 主動 refetch。
class ApiHeritageSyncService implements HeritageSyncService {
  ApiHeritageSyncService(this._client);

  final ApiClient _client;

  @override
  Future<HeritageBoardSnapshot> fetchItems(int groupId) async {
    final m = await _client.sendJson('POST', '/api/item',
        body: {'group_id': groupId}) as Map<String, dynamic>;
    final inventory = <OwnedItem>[
      for (final e in (m['inventory'] as List? ?? const []))
        OwnedItem(
          itemId: ((e as Map)['item_id'] as num?)?.toInt() ?? 0,
          type: (e['type'] as num).toInt(),
          questionId: (e['question_id'] as num?)?.toInt() ?? 0,
        ),
    ];
    final slots = <int, SlotItem>{};
    final rawSlots = m['slots'] as Map<String, dynamic>? ?? const {};
    rawSlots.forEach((k, v) {
      final mm = v as Map<String, dynamic>;
      slots[int.parse(k)] = SlotItem(
        itemId: (mm['item_id'] as num?)?.toInt() ?? 0,
        type: (mm['type'] as num).toInt(),
        questionId: (mm['question_id'] as num?)?.toInt() ?? 0,
        broken: mm['broken'] == true,
      );
    });
    return HeritageBoardSnapshot(inventory: inventory, slots: slots);
  }

  @override
  Future<bool> placeItem({
    required int groupId,
    required int itemId,
    required int slotId,
  }) async {
    try {
      await _client.sendJson('POST', '/api/item/inv2slot',
          body: {'group_id': groupId, 'item_id': itemId, 'slot_id': slotId});
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 403) throw const GroupChangedException();
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeItem({required int groupId, required int slotId}) async {
    try {
      await _client.sendJson('POST', '/api/item/slot2inv',
          body: {'group_id': groupId, 'slot_id': slotId});
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 403) throw const GroupChangedException();
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int?> grantItem({required int groupId, required int type}) {
    // 後端採集獎勵由 quiz answer 入庫，不該走這裡。
    throw UnsupportedError('採集獎勵由後端於答對題目時入庫，請用 quiz answer 回的 item_id 後 refresh');
  }

  @override
  Stream<HeritageBoardSnapshot> watch(int groupId) =>
      const Stream<HeritageBoardSnapshot>.empty();

  @override
  void dispose() {}
}
