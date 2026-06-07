import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/component_model.dart';
import '../services/heritage_sync_service.dart';

/// 管理「某組在某古蹟」的背包與放置狀態，供我的古蹟 / 編輯古蹟共用。
///
/// 透過 [HeritageSyncService] 讀寫，並訂閱其即時推播，因此其他裝置（或攻防戰）
/// 造成的變動會自動反映在 UI。前端在此負責 [ComponentModel.allowedSlotIds] 驗證。
class HeritageBoardController extends ChangeNotifier {
  final HeritageSyncService service;
  HeritageBoardController(this.service);

  int? _groupId;
  String _heritageId = '';
  bool _loading = false;
  Map<int, int> _inventory = {}; // item_id → 數量
  Map<int, int> _slots = {}; // slot_id → item_id
  StreamSubscription<HeritageBoardSnapshot>? _sub;

  bool get isLoading => _loading;
  String get heritageId => _heritageId;
  Map<int, int> get inventory => Map.unmodifiable(_inventory);
  Map<int, int> get slots => Map.unmodifiable(_slots);

  int qty(int itemId) => _inventory[itemId] ?? 0;
  int? itemAt(int slotId) => _slots[slotId];
  bool isSlotFilled(int slotId) => _slots.containsKey(slotId);

  /// 背包中尚未使用（未放上 slot）的原料總數。
  int get unusedCount => _inventory.values.fold(0, (a, b) => a + b);

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

    _inventory = await service.fetchInventory(groupId);
    _slots = await service.fetchSlots(groupId);
    _loading = false;
    notifyListeners();

    await _sub?.cancel();
    _sub = service.watch(groupId).listen((snap) {
      _inventory = snap.inventory;
      _slots = snap.slots;
      notifyListeners();
    });
  }

  /// 此元件是否可放進該 slot：背包有貨 + slot 空 + 符合 allowedSlotIds。
  bool canPlace(ComponentModel c, int slotId) =>
      qty(c.id) > 0 && !isSlotFilled(slotId) && c.canPlaceIn(slotId);

  Future<bool> place(ComponentModel c, int slotId) async {
    if (_groupId == null || !canPlace(c, slotId)) return false;
    return service.placeItem(groupId: _groupId!, itemId: c.id, slotId: slotId);
  }

  Future<bool> removeAt(int slotId) async {
    if (_groupId == null) return false;
    return service.removeItem(groupId: _groupId!, slotId: slotId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
