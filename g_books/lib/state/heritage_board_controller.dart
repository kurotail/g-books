import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/component_data.dart' show componentsByLevel;
import '../data/models/component_model.dart';
import '../services/heritage_sync_service.dart';

/// 管理「某組在某古蹟」的背包與放置狀態，供我的古蹟 / 編輯古蹟共用。
///
/// 透過 [HeritageSyncService] 讀寫，並訂閱其即時推播。對內保存後端形狀的物品實例
/// （[OwnedItem] / [SlotItem]），對外提供「type（原料 id）→數量」「slotId→type」等
/// 好用介面，畫面不必感知 item_id；放置時才從背包挑一個該 type 的實例送出。
/// 前端在此負責 [ComponentModel.allowedSlotIds] 驗證（與後端 item_allowed_slot 一致）。
class HeritageBoardController extends ChangeNotifier {
  final HeritageSyncService service;
  HeritageBoardController(this.service);

  int? _groupId;
  String _heritageId = '';
  bool _loading = false;
  List<OwnedItem> _inventory = []; // 散裝實例
  Map<int, SlotItem> _slots = {}; // slot_id → 物品
  StreamSubscription<HeritageBoardSnapshot>? _sub;

  bool get isLoading => _loading;
  String get heritageId => _heritageId;

  /// 背包：type（原料 id）→ 持有數量。
  Map<int, int> get inventory {
    final m = <int, int>{};
    for (final it in _inventory) {
      m[it.type] = (m[it.type] ?? 0) + 1;
    }
    return Map.unmodifiable(m);
  }

  /// 已放置：slot_id → type（原料 id）。
  Map<int, int> get slots {
    final m = <int, int>{};
    _slots.forEach((s, it) => m[s] = it.type);
    return Map.unmodifiable(m);
  }

  /// 背包中該 type 的持有數量。
  int qty(int type) => _inventory.where((it) => it.type == type).length;

  /// 該 slot 上的物品 type（原料 id），空則 null。
  int? itemAt(int slotId) => _slots[slotId]?.type;

  /// 依 item_id（實例）找其 type（原料 id），背包 / slot 都找；找不到回 null。
  /// 採集答對後後端回 item_id，刷新背包後用此查出對應原料以顯示獎勵。
  int? typeOfItemId(int itemId) {
    for (final it in _inventory) {
      if (it.itemId == itemId) return it.type;
    }
    for (final it in _slots.values) {
      if (it.itemId == itemId) return it.type;
    }
    return null;
  }

  bool isSlotFilled(int slotId) => _slots.containsKey(slotId);

  /// 該 slot 上的物品是否已損毀（攻防戰打壞）。
  bool isBroken(int slotId) => _slots[slotId]?.broken ?? false;

  /// 背包中尚未使用（未放上 slot）的原料總數。
  int get unusedCount => _inventory.length;

  /// 已放上 slot 的元件數。
  int get usedCount => _slots.length;

  /// 擁有的元件總數（未使用 + 已使用）。
  int get totalCount => unusedCount + usedCount;

  /// 綁定到指定組別 / 古蹟並載入狀態（重複綁定相同對象為 no-op）。
  Future<void> bind({required int groupId, required String heritageId}) async {
    if (_groupId == groupId && _heritageId == heritageId) return;
    _groupId = groupId;
    _heritageId = heritageId;
    _loading = true;
    notifyListeners();

    final snap = await service.fetchItems(groupId);
    _inventory = snap.inventory;
    _slots = snap.slots;
    _loading = false;
    notifyListeners();

    await _sub?.cancel();
    _sub = service.watch(groupId).listen((snap) {
      _inventory = snap.inventory;
      _slots = snap.slots;
      notifyListeners();
    });
  }

  /// 重新向服務取背包（自身 mutation 或採集獎勵後同步；後端無背包推播時靠這個）。
  Future<void> refresh() async {
    final g = _groupId;
    if (g == null) return;
    final snap = await service.fetchItems(g);
    _inventory = snap.inventory;
    _slots = snap.slots;
    notifyListeners();
  }

  /// 此元件是否可放進該 slot：背包有貨 + slot 空 + 符合 allowedSlotIds。
  bool canPlace(ComponentModel c, int slotId) =>
      qty(c.id) > 0 && !isSlotFilled(slotId) && c.canPlaceIn(slotId);

  Future<bool> place(ComponentModel c, int slotId) async {
    final g = _groupId;
    if (g == null || !canPlace(c, slotId)) return false;
    // 從背包挑一個該 type 的實例，用它的 item_id 放置。
    final idx = _inventory.indexWhere((it) => it.type == c.id);
    if (idx < 0) return false;
    final ok =
        await service.placeItem(groupId: g, itemId: _inventory[idx].itemId, slotId: slotId);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> removeAt(int slotId) async {
    final g = _groupId;
    if (g == null) return false;
    final ok = await service.removeItem(groupId: g, slotId: slotId);
    if (ok) await refresh();
    return ok;
  }

  /// 發一個指定原料到背包（資源採集獎勵；本機 mock 用）。成功回 true。
  Future<bool> grantItem(int type) async {
    final g = _groupId;
    if (g == null) return false;
    final id = await service.grantItem(groupId: g, type: type);
    if (id != null) await refresh();
    return id != null;
  }

  /// 依等級（1~3）隨機發一個目前古蹟的原料到背包（資源採集獎勵）。
  /// 回傳實際發出的原料；該等級無原料或尚未綁定組別時回 null。
  Future<ComponentModel?> grantRandomOfLevel(int level) async {
    if (_groupId == null) return null;
    final pool = componentsByLevel(_heritageId, level);
    if (pool.isEmpty) return null;
    final comp = pool[Random().nextInt(pool.length)];
    final ok = await grantItem(comp.id);
    return ok ? comp : null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
