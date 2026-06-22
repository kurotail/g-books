import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../data/models/heritage_config.dart';
import '../data/models/heritage_slot.dart';
import 'api_client.dart';

/// 古蹟設定（slot 幾何 / 原料→slot 對應 / 原料中繼資料）的資料來源抽象層。
///
/// 管理者編輯流程：[fetch] 取設定 → 編輯 → [save] 同步回後端。格式沿用現有：
/// slots = 陣列、component_slots = `{cid:[slotId]}`、components = `{cid:{name,level}}`，
/// 空設定即 `[]` / `{}`。後端實作見 [ApiHeritageConfigService]、離線開發見
/// [LocalHeritageConfigService]，在 `main.dart` 切換實作即可，UI 不需更動。
///
/// 古蹟設定的單一真相在後端 building；assets 不再保存設定 json。學生端執行設定由
/// [StudentConfigLoader] 於登入後依 building_id 取得並快取本機（離線回退）。
abstract class HeritageConfigService {
  Future<HeritageConfig> fetch(String heritageId);
  Future<void> save(String heritageId, HeritageConfig config);
}

// ── 共用解析（字串或已解碼皆可；空 / null → 空）─────────────────────────────────
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

/// 後端 building 的 `building_id`（缺值回 0）。
int buildingIdOf(Map<String, dynamic> b) =>
    (b['building_id'] as num?)?.toInt() ?? 0;

/// 後端 building 的 `name`（= heritageId；缺值回空字串）。
String buildingNameOf(Map<String, dynamic> b) => (b['name'] as String?) ?? '';

/// 把後端 building（`{name, layout, item_allowed_slot, difficulty_type}`）解析成
/// [HeritageConfig]。Layout 內帶 `slots` / `components`；component 名稱/等級優先取
/// layout.components，缺則由 difficulty_type 還原等級、名稱用預設。
HeritageConfig heritageConfigFromBuilding(Map<String, dynamic> b) {
  Map<String, dynamic> layout = const {};
  final raw = b['layout'];
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is Map) layout = d.cast<String, dynamic>();
    } catch (_) {}
  }
  var components = _componentsFromJson(layout['components']);
  if (components.isEmpty) {
    components = _componentsFromDifficulty(b['difficulty_type']);
  }
  return HeritageConfig(
    slots: _slotsFromJson(layout['slots']),
    componentSlots: _componentSlotsFromJson(b['item_allowed_slot']),
    components: components,
    mapCells: _slotsFromJson(layout['mapCells']),
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

/// 把 [HeritageConfig] 序列化成三段 JSON 字串（縮排、key 排序），鍵為
/// `slots` / `component_slots` / `components`。本機保存（admin 假後端、學生快取）共用。
Map<String, String> serializeHeritageConfig(HeritageConfig c) {
  const enc = JsonEncoder.withIndent('  ');
  final slots = enc.convert(c.slots.map((s) => s.toJson()).toList());
  final mapCells = enc.convert(c.mapCells.map((s) => s.toJson()).toList());

  final cs = <String, List<int>>{};
  for (final e in c.componentSlots.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    cs['${e.key}'] = e.value.toList()..sort();
  }
  final componentSlots = enc.convert(cs);

  final cm = <String, dynamic>{};
  for (final e in c.components.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    cm['${e.key}'] = e.value.toJson();
  }
  final components = enc.convert(cm);

  return {
    'slots': slots,
    'component_slots': componentSlots,
    'components': components,
    'map_cells': mapCells,
  };
}

/// 假後端：以 App 文件區的本機檔案保存。供離線開發時管理者「請求 → 編輯 → 儲存」整個
/// 迴圈可運作。assets 已不再保存設定 json，故首次（無本機檔）回空白設定讓管理者建立。
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

    // 任一檔不存在 → 視為首次：給空白設定並寫回（assets 已無種子）。
    if (!await slotsFile.exists() ||
        !await compSlotsFile.exists() ||
        !await compFile.exists()) {
      final seeded = HeritageConfig();
      await save(hid, seeded);
      return seeded;
    }
    // map_cells.json 為後加欄位：不存在時視為空（不強制重新種子化）。
    final mapCellsFile = File('${dir.path}/map_cells.json');
    return HeritageConfig(
      slots: _slotsFromJson(await slotsFile.readAsString()),
      componentSlots: _componentSlotsFromJson(await compSlotsFile.readAsString()),
      components: _componentsFromJson(await compFile.readAsString()),
      mapCells: await mapCellsFile.exists()
          ? _slotsFromJson(await mapCellsFile.readAsString())
          : const [],
    );
  }

  @override
  Future<void> save(String hid, HeritageConfig c) async {
    await Future<void>.delayed(_netDelay);
    final dir = await _dir(hid);
    final j = serializeHeritageConfig(c);
    await File('${dir.path}/slots.json').writeAsString(j['slots']!);
    await File('${dir.path}/component_slots.json')
        .writeAsString(j['component_slots']!);
    await File('${dir.path}/components.json').writeAsString(j['components']!);
    await File('${dir.path}/map_cells.json').writeAsString(j['map_cells']!);
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
      if (buildingNameOf(m) == hid) {
        _idCache[hid] = buildingIdOf(m);
        return m;
      }
    }
    return null;
  }

  @override
  Future<HeritageConfig> fetch(String hid) async {
    final b = await _findBuilding(hid);
    // 後端尚無此古蹟 building → 回空白設定，管理者編輯後 save 會建立。
    if (b == null) return HeritageConfig();
    return heritageConfigFromBuilding(b);
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
      _idCache[hid] = buildingIdOf(res.cast<String, dynamic>());
    }
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
      'mapCells': [for (final s in c.mapCells) s.toJson()],
    });
    return {
      'name': hid,
      'layout': layout,
      'item_allowed_slot': allowed,
      'difficulty_type': diff,
    };
  }
}

/// 學生端執行設定的載入：登入後依該組 `building_id` 取後端 building 設定。
///
/// 線上成功 → 套用並寫入本機快取（`gb_cache/building_<id>/`）；離線 / 失敗 → 回退讀
/// 該 building 的本機快取（上次成功的設定）。古蹟設定單一真相在後端，本機快取只供離線
/// 沿用、不供編輯。[load] 回 null 表示線上取不到且無快取（例如首次就離線、或尚未指派
/// building）。mock 模式（[_client] 為 null）只走快取。
class StudentConfigLoader {
  StudentConfigLoader(this._client);

  final ApiClient? _client; // mock 模式為 null

  Future<({String heritageId, HeritageConfig config})?> load(
      int buildingId) async {
    if (buildingId <= 0) return null;
    final client = _client;
    if (client != null) {
      try {
        final b = await client.getJson('/api/building/$buildingId')
            as Map<String, dynamic>;
        final hid = buildingNameOf(b);
        final cfg = heritageConfigFromBuilding(b);
        await _writeCache(buildingId, hid, cfg);
        return (heritageId: hid, config: cfg);
      } catch (_) {
        // 線上取設定失敗 → 落到本機快取。
      }
    }
    return _readCache(buildingId);
  }

  Future<Directory> _cacheDir(int buildingId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/gb_cache/building_$buildingId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _writeCache(int buildingId, String hid, HeritageConfig c) async {
    try {
      final dir = await _cacheDir(buildingId);
      final j = serializeHeritageConfig(c);
      await File('${dir.path}/heritage_id').writeAsString(hid);
      await File('${dir.path}/slots.json').writeAsString(j['slots']!);
      await File('${dir.path}/component_slots.json')
          .writeAsString(j['component_slots']!);
      await File('${dir.path}/components.json').writeAsString(j['components']!);
      await File('${dir.path}/map_cells.json').writeAsString(j['map_cells']!);
    } catch (_) {
      // 快取寫入失敗不影響本次顯示。
    }
  }

  Future<({String heritageId, HeritageConfig config})?> _readCache(
      int buildingId) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/gb_cache/building_$buildingId');
      final idFile = File('${dir.path}/heritage_id');
      if (!await idFile.exists()) return null;
      final hid = (await idFile.readAsString()).trim();
      if (hid.isEmpty) return null;
      final cfg = HeritageConfig(
        slots: _slotsFromJson(await _readOrNull(dir, 'slots.json')),
        componentSlots:
            _componentSlotsFromJson(await _readOrNull(dir, 'component_slots.json')),
        components: _componentsFromJson(await _readOrNull(dir, 'components.json')),
        mapCells: _slotsFromJson(await _readOrNull(dir, 'map_cells.json')),
      );
      return (heritageId: hid, config: cfg);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readOrNull(Directory dir, String name) async {
    final f = File('${dir.path}/$name');
    return await f.exists() ? f.readAsString() : null;
  }
}
