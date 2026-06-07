import 'dart:async';

/// 某組古蹟的背包 + 放置狀態快照。
class HeritageBoardSnapshot {
  /// 背包：item_id → 擁有數量。
  final Map<int, int> inventory;

  /// 已放置：slot_id → item_id。
  final Map<int, int> slots;

  const HeritageBoardSnapshot({required this.inventory, required this.slots});

  HeritageBoardSnapshot copy() => HeritageBoardSnapshot(
        inventory: Map<int, int>.from(inventory),
        slots: Map<int, int>.from(slots),
      );
}

/// 編輯古蹟 / 我的古蹟的資料來源抽象層。
///
/// 對應後端 `gb_api`：
///   - [fetchInventory] ↔ `POST /api/item/inv`
///   - [fetchSlots]     ↔ `POST /api/item/slot`
///   - [placeItem]      ↔ `POST /api/item/inv2slot`
///   - [removeItem]     ↔ `POST /api/item/slot2inv`
///   - [watch]          ↔ 未來的 WebSocket 背包/slot 變動推播（目前後端 WS
///                         只推 NORMAL/QUIZ 狀態，故先以本機事件模擬）
///
/// ⚠️ 後端 inv2slot/slot2inv **不驗證**「此元件是否可放此 slot」，該規則
/// （[ComponentModel.allowedSlotIds]）由前端負責驗證。
abstract class HeritageSyncService {
  Future<Map<int, int>> fetchInventory(int groupId);

  Future<Map<int, int>> fetchSlots(int groupId);

  /// 放一個 [itemId] 進 [slotId]；成功回 true。
  Future<bool> placeItem({
    required int groupId,
    required int itemId,
    required int slotId,
  });

  /// 把 [slotId] 上的元件收回背包；成功回 true。
  Future<bool> removeItem({
    required int groupId,
    required int slotId,
  });

  /// 訂閱該組的即時變動（其他裝置 / 攻防戰造成）。連線時先送一份目前快照。
  Stream<HeritageBoardSnapshot> watch(int groupId);

  void dispose() {}
}

/// 本機 mock 實作：以記憶體保存各組狀態，place/remove 後即時透過 [watch] 推播，
/// 模擬「多裝置同步」。之後替換為 `ApiHeritageSyncService` 即可，UI 不需更動。
class MockHeritageSyncService implements HeritageSyncService {
  // groupId → 狀態
  final Map<int, Map<int, int>> _inventory = {};
  final Map<int, Map<int, int>> _slots = {};
  final Map<int, StreamController<HeritageBoardSnapshot>> _controllers = {};

  /// 預設背包庫存（item_id → 數量），方便開發測試。
  static const Map<int, int> _seedInventory = {
    1: 2, 2: 1, 3: 3, 4: 1, // lv1
    5: 1, 6: 1, 7: 2, // lv2
    9: 1, 11: 1, // lv3
  };

  Map<int, int> _inv(int g) => _inventory.putIfAbsent(
        g,
        () => Map<int, int>.from(_seedInventory),
      );

  Map<int, int> _slt(int g) => _slots.putIfAbsent(g, () => <int, int>{});

  StreamController<HeritageBoardSnapshot> _ctrl(int g) =>
      _controllers.putIfAbsent(
        g,
        () => StreamController<HeritageBoardSnapshot>.broadcast(),
      );

  HeritageBoardSnapshot _snapshot(int g) => HeritageBoardSnapshot(
        inventory: Map<int, int>.from(_inv(g)),
        slots: Map<int, int>.from(_slt(g)),
      );

  void _emit(int g) {
    if (_controllers.containsKey(g)) _ctrl(g).add(_snapshot(g));
  }

  @override
  Future<Map<int, int>> fetchInventory(int groupId) async =>
      Map<int, int>.from(_inv(groupId));

  @override
  Future<Map<int, int>> fetchSlots(int groupId) async =>
      Map<int, int>.from(_slt(groupId));

  @override
  Future<bool> placeItem({
    required int groupId,
    required int itemId,
    required int slotId,
  }) async {
    final inv = _inv(groupId);
    final have = inv[itemId] ?? 0;
    if (have <= 0) return false;
    final slots = _slt(groupId);
    if (slots.containsKey(slotId)) return false; // 該 slot 已被佔用

    if (have - 1 <= 0) {
      inv.remove(itemId);
    } else {
      inv[itemId] = have - 1;
    }
    slots[slotId] = itemId;
    _emit(groupId);
    return true;
  }

  @override
  Future<bool> removeItem({
    required int groupId,
    required int slotId,
  }) async {
    final slots = _slt(groupId);
    final itemId = slots.remove(slotId);
    if (itemId == null) return false;
    final inv = _inv(groupId);
    inv[itemId] = (inv[itemId] ?? 0) + 1;
    _emit(groupId);
    return true;
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
