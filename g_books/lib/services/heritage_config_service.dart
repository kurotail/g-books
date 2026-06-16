import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/component_data.dart' show seedComponentMetaOf;
import '../data/models/heritage_config.dart';
import '../data/models/heritage_slot.dart';
import 'api_client.dart';

/// 古蹟設定（slot 幾何 / 原料→slot 對應 / 原料中繼資料）的資料來源抽象層。
///
/// 管理者編輯流程：[fetch] 取設定 → 編輯 → [save] 同步回後端。格式沿用現有：
/// slots = 陣列、component_slots = `{cid:[slotId]}`、components = `{cid:{name,level}}`，
/// 空設定即 `[]` / `{}`。後端實作見 [ApiHeritageConfigService]、離線開發見
/// [LocalHeritageConfigService]，在 `main.dart` 切換實作即可，UI 不需更動。
abstract class HeritageConfigService {
  Future<HeritageConfig> fetch(String heritageId);
  Future<void> save(String heritageId, HeritageConfig config);
}

// ── 共用：種子化 + 解析（被 Local / Api / 啟動顯示種子共用）──────────────────────
Future<String?> _tryAsset(String path) async {
  try {
    return await rootBundle.loadString(path);
  } catch (_) {
    return null;
  }
}

/// 解析 slots：接受 JSON 字串或已解碼的 List；空 / null → 空。
List<HeritageSlot> _slotsFromJson(dynamic raw) {
  if (raw == null) return [];
  final list = raw is String
      ? (raw.trim().isEmpty ? const [] : jsonDecode(raw) as List)
      : raw as List;
  return list
      .map((e) => HeritageSlot.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}

/// 解析 `{cid:[slotId...]}`：接受 JSON 字串或已解碼的 Map。
Map<int, Set<int>> _componentSlotsFromJson(dynamic raw) {
  if (raw == null) return {};
  final map = raw is String
      ? (raw.trim().isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>())
      : (raw as Map).cast<String, dynamic>();
  return {
    for (final e in map.entries)
      int.parse(e.key):
          (e.value as List).map((x) => (x as num).toInt()).toSet(),
  };
}

/// 解析 `{cid:{name,level}}`：接受 JSON 字串或已解碼的 Map。
Map<int, ComponentMeta> _componentsFromJson(dynamic raw) {
  if (raw == null) return {};
  final map = raw is String
      ? (raw.trim().isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>())
      : (raw as Map).cast<String, dynamic>();
  return {
    for (final e in map.entries)
      int.parse(e.key):
          ComponentMeta.fromJson((e.value as Map).cast<String, dynamic>()),
  };
}

/// 首次無資料時，從現有 assets / dart 取古蹟設定初值（純讀取、不寫任何持久層）。
/// 供啟動時的學生端顯示種子、以及兩種服務「後端 / 本機尚無資料」時的回退。
Future<HeritageConfig> seedHeritageConfigFromAssets(String hid) async {
  return HeritageConfig(
    slots: _slotsFromJson(await _tryAsset('assets/data/slots/$hid.json')),
    componentSlots:
        _componentSlotsFromJson(await _tryAsset('assets/data/component_slots/$hid.json')),
    components: seedComponentMetaOf(hid),
  );
}

/// 假後端：以 App 文件區的本機檔案保存。首次（無本機檔）時以 assets / dart 種子化並
/// 寫回，之後即以本機檔為準 —— 讓「請求 → 編輯 → 儲存」整個迴圈在離線開發時可運作。
class LocalHeritageConfigService implements HeritageConfigService {
  static const _netDelay = Duration(milliseconds: 250); // 模擬網路往返

  Future<Directory> _dir(String hid) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/gb_admin/$hid');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<HeritageConfig> fetch(String hid) async {
    await Future<void>.delayed(_netDelay);
    final dir = await _dir(hid);
    final slotsFile = File('${dir.path}/slots.json');
    final compSlotsFile = File('${dir.path}/component_slots.json');
    final compFile = File('${dir.path}/components.json');

    // 任一檔不存在 → 視為首次，種子化並寫回。
    if (!await slotsFile.exists() ||
        !await compSlotsFile.exists() ||
        !await compFile.exists()) {
      final seeded = await seedHeritageConfigFromAssets(hid);
      await save(hid, seeded);
      return seeded;
    }
    return HeritageConfig(
      slots: _slotsFromJson(await slotsFile.readAsString()),
      componentSlots: _componentSlotsFromJson(await compSlotsFile.readAsString()),
      components: _componentsFromJson(await compFile.readAsString()),
    );
  }

  @override
  Future<void> save(String hid, HeritageConfig c) async {
    await Future<void>.delayed(_netDelay);
    final dir = await _dir(hid);
    const enc = JsonEncoder.withIndent('  ');

    await File('${dir.path}/slots.json')
        .writeAsString(enc.convert(c.slots.map((s) => s.toJson()).toList()));

    final cs = <String, List<int>>{};
    for (final e in c.componentSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      cs['${e.key}'] = e.value.toList()..sort();
    }
    await File('${dir.path}/component_slots.json').writeAsString(enc.convert(cs));

    final cm = <String, dynamic>{};
    for (final e in c.components.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      cm['${e.key}'] = e.value.toJson();
    }
    await File('${dir.path}/components.json').writeAsString(enc.convert(cm));
  }
}

/// 後端實作：管理者古蹟編輯器把設定存進 `gb_api` 的 Building（需管理者 JWT）。
///
/// 對映 —— Layout 存一段 JSON（slot 幾何 + 原料名稱/等級）、`item_allowed_slot`=
/// 原料→可放 slot、`difficulty_type`=等級→原料。古蹟↔building 以 `Building.name`
/// == heritageId 配對：存在就 PUT、不存在就 POST。
class ApiHeritageConfigService implements HeritageConfigService {
  ApiHeritageConfigService(this._client);

  final ApiClient _client;
  final Map<String, int> _idCache = {}; // heritageId → building_id

  /// 列出所有 building，找 `name == hid`；找到順手記住 building_id。
  Future<Map<String, dynamic>?> _findBuilding(String hid) async {
    final list = await _client.getJson('/api/building');
    if (list is! List) return null;
    for (final b in list) {
      final m = (b as Map).cast<String, dynamic>();
      if (m['name'] == hid) {
        _idCache[hid] = (m['building_id'] as num).toInt();
        return m;
      }
    }
    return null;
  }

  @override
  Future<HeritageConfig> fetch(String hid) async {
    final b = await _findBuilding(hid);
    // 後端尚無此古蹟 building → 用 assets 初值，管理者編輯後 save 會建立。
    if (b == null) return seedHeritageConfigFromAssets(hid);
    return _toConfig(b);
  }

  @override
  Future<void> save(String hid, HeritageConfig c) async {
    if (!_idCache.containsKey(hid)) await _findBuilding(hid);
    final id = _idCache[hid];
    final body = _toRequest(hid, c);
    final res = id == null
        ? await _client.sendJson('POST', '/api/building', body: body)
        : await _client.sendJson('PUT', '/api/building/$id', body: body);
    if (res is Map && res['building_id'] != null) {
      _idCache[hid] = (res['building_id'] as num).toInt();
    }
  }

  HeritageConfig _toConfig(Map<String, dynamic> b) {
    Map<String, dynamic> layout = const {};
    final raw = b['layout'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) layout = d.cast<String, dynamic>();
      } catch (_) {}
    }
    var components = _componentsFromJson(layout['components']);
    // Layout 沒帶 components 時（例如其他工具建的 building），至少用
    // difficulty_type 還原等級，名稱用預設。
    if (components.isEmpty) {
      components = _componentsFromDifficulty(b['difficulty_type']);
    }
    return HeritageConfig(
      slots: _slotsFromJson(layout['slots']),
      componentSlots: _componentSlotsFromJson(b['item_allowed_slot']),
      components: components,
    );
  }

  Map<int, ComponentMeta> _componentsFromDifficulty(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, ComponentMeta>{};
    for (final e in raw.entries) {
      final level = int.tryParse(e.key.toString()) ?? 1;
      for (final t in (e.value as List)) {
        final cid = (t as num).toInt();
        out[cid] = ComponentMeta(name: '原料$cid', level: level);
      }
    }
    return out;
  }

  Map<String, dynamic> _toRequest(String hid, HeritageConfig c) {
    final allowed = <String, List<int>>{};
    for (final e in c.componentSlots.entries) {
      allowed['${e.key}'] = e.value.toList()..sort();
    }
    final diff = <String, List<int>>{};
    for (final e in c.components.entries) {
      (diff['${e.value.level}'] ??= []).add(e.key);
    }
    for (final v in diff.values) {
      v.sort();
    }
    final layout = jsonEncode({
      'heritageId': hid,
      'slots': [for (final s in c.slots) s.toJson()],
      'components': {
        for (final e in c.components.entries) '${e.key}': e.value.toJson(),
      },
    });
    return {
      'name': hid,
      'layout': layout,
      'item_allowed_slot': allowed,
      'difficulty_type': diff,
    };
  }
}
