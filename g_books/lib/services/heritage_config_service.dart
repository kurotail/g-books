import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/component_data.dart' show seedComponentMetaOf;
import '../data/models/heritage_config.dart';
import '../data/models/heritage_slot.dart';

/// 古蹟設定（slot 幾何 / 原料→slot 對應 / 原料中繼資料）的資料來源抽象層。
///
/// 管理者編輯流程：[fetch] 取設定 → 編輯 → [save] 同步回後端。格式沿用現有：
/// slots = 陣列、component_slots = `{cid:[slotId]}`、components = `{cid:{name,level}}`，
/// 空設定即 `[]` / `{}`。之後換真後端只要新增 `ApiHeritageConfigService` 並在
/// `main.dart` 換掉實作，前端與 UI 不需更動。
abstract class HeritageConfigService {
  Future<HeritageConfig> fetch(String heritageId);
  Future<void> save(String heritageId, HeritageConfig config);
}

/// 假後端：以 App 文件區的本機檔案保存。首次（無本機檔）時，以現有 assets / dart
/// 種子化並寫回，之後即以本機檔為準 —— 讓「請求 → 編輯 → 儲存」整個迴圈可運作、
/// 且重開 App 後編輯結果仍在。
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
      final seeded = await _seed(hid);
      await save(hid, seeded);
      return seeded;
    }
    return HeritageConfig(
      slots: _parseSlots(await slotsFile.readAsString()),
      componentSlots: _parseComponentSlots(await compSlotsFile.readAsString()),
      components: _parseComponents(await compFile.readAsString()),
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

  // ── 種子化：首次無本機檔時，從現有 assets / dart 取初值 ───────────────────────
  Future<HeritageConfig> _seed(String hid) async {
    return HeritageConfig(
      slots: _parseSlots(await _tryAsset('assets/data/slots/$hid.json')),
      componentSlots: _parseComponentSlots(
        await _tryAsset('assets/data/component_slots/$hid.json'),
      ),
      components: seedComponentMetaOf(hid),
    );
  }

  Future<String?> _tryAsset(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }

  // ── parsing（沿用現有格式，空 / 缺檔 → 空集合）────────────────────────────────
  List<HeritageSlot> _parseSlots(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => HeritageSlot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<int, Set<int>> _parseComponentSlots(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        int.parse(e.key): (e.value as List).map((x) => (x as num).toInt()).toSet(),
    };
  }

  Map<int, ComponentMeta> _parseComponents(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        int.parse(e.key): ComponentMeta.fromJson(e.value as Map<String, dynamic>),
    };
  }
}
