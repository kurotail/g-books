/// 題庫匯入：把 `quest.csv`（欄位：題目, A, B, C, D, 答案, 難度）解析、分類成後端
/// `POST /api/question/upload` 的 payload。純邏輯、無 IO，App 內 ZIP 匯入器與 seed
/// 腳本（seed/seed_questions.py）共用同一套規則。
///
/// 答案可有多個正解（後端 answer.data 為「非空陣列」；學生只需答對其一）。同一格內以
/// 直線 `|` 分隔多個正解，單一答案維持原樣即可（會變成 1 元素陣列）。
///
/// 題型判斷：
///   - 題目欄是音檔路徑   → 語音敘述題（description.type = audio）
///   - A~D 皆空           → 語音作答題（answer.type = voice_response）；答案欄為可接受的
///                          「辨識文字」清單（後端以 STT 轉文字後比對，不分大小寫）。
///                          答案欄可直接填文字，或填參考音檔（如 q1.wav）由 STT 轉成文字：
///                          App 內匯入透過後端 `POST /api/stt`（教師限定）轉檔，seed 腳本則
///                          直接連本機 STT。[buildQuestionPayload] 以 [resolveTranscript]
///                          回呼取得音檔的辨識文字；未提供回呼時，音檔答案會丟例外。
///   - A~D 有值           → 選擇題（answer.type = index）；答案欄為一或多個字母（如 A 或
///                          A|C）。選項若為音檔則以其 URL 當選項字串（後端選項型別仍是
///                          text，不需改後端；學生端 UI 需自行渲染成播放鈕）。
library;

/// 採集 / 平時（NORMAL・QUIZ1）。
const int kAreaCollect = 1;

/// 攻防戰（QUIZ2）。
const int kAreaFight = 2;

/// 各難度分到攻防戰(area 2)的比例，其餘進採集(area 1)。
const double kQuiz2Ratio = 0.25;

/// 後端 media 服務接受的音檔副檔名（見 gb_api internal/service/media.go）。
const Set<String> _audioExts = {
  '.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac', '.aiff',
};

const List<String> _letters = ['A', 'B', 'C', 'D'];

/// 欄位值是否為音檔路徑（依副檔名判斷）。
bool isAudioPath(String value) {
  final v = value.trim().toLowerCase();
  final dot = v.lastIndexOf('.');
  if (dot < 0) return false;
  return _audioExts.contains(v.substring(dot));
}

/// 把答案欄拆成多個正解（以 `|` 分隔），去除前後空白與空項。
List<String> splitAnswers(String cell) =>
    cell.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// 解析後的一列題目（[area] 由 [assignAreas] 填入）。
class QuestRow {
  QuestRow({
    required this.prompt,
    required this.options,
    required this.answer,
    required this.difficulty,
    required this.line,
  });

  final String prompt;
  final List<String> options; // 長度 4：A, B, C, D
  final String answer;
  final int difficulty;
  final int line; // CSV 行號（1-based，供錯誤訊息定位）
  int area = kAreaCollect;
}

/// [parseQuestCsv] 的結果：成功列、警告（略過的列原因），以及兩種音檔引用：
///   - [audioRefs]       題目敘述 / 選項的音檔 → 需上傳到 `/api/audio` 換 URL。
///   - [answerAudioRefs] 語音作答題答案欄的參考音檔 → 需經 STT 轉成辨識文字。
class QuestParseResult {
  QuestParseResult(
    this.rows,
    this.warnings,
    this.audioRefs,
    this.answerAudioRefs,
  );

  final List<QuestRow> rows;
  final List<String> warnings;
  final Set<String> audioRefs;
  final Set<String> answerAudioRefs;
}

/// 解析 quest.csv 文字（容許 BOM / CRLF / 引號欄位）。第一非空列視為欄名跳過。
QuestParseResult parseQuestCsv(String text) {
  final table = _parseCsv(text.startsWith('﻿') ? text.substring(1) : text);
  final rows = <QuestRow>[];
  final warnings = <String>[];
  final audioRefs = <String>{};
  final answerAudioRefs = <String>{};

  var seenHeader = false;
  for (var i = 0; i < table.length; i++) {
    final raw = table[i].map((c) => c.trim()).toList();
    if (raw.every((c) => c.isEmpty)) continue;
    if (!seenHeader) {
      seenHeader = true; // 跳過欄名列
      continue;
    }
    final line = i + 1;
    final cells = [...raw, '', '', '', '', '', '', ''].sublist(0, 7);
    final prompt = cells[0];
    final options = cells.sublist(1, 5);
    final answer = cells[5];
    final diff = int.tryParse(cells[6]);
    if (prompt.isEmpty) {
      warnings.add('第 $line 列：題目為空，略過');
      continue;
    }
    if (diff == null) {
      warnings.add('第 $line 列：難度「${cells[6]}」非數字，略過');
      continue;
    }
    rows.add(QuestRow(
      prompt: prompt,
      options: options,
      answer: answer,
      difficulty: diff,
      line: line,
    ));
    // 題目敘述與選項的音檔 → 需上傳換 URL。
    for (final v in [prompt, ...options]) {
      if (isAudioPath(v)) audioRefs.add(v.trim());
    }
    // 語音作答題（A~D 皆空）的答案欄可填參考音檔 → 需經 STT 轉成辨識文字；先收集起來。
    if (options.every((o) => o.isEmpty)) {
      for (final t in splitAnswers(answer)) {
        if (isAudioPath(t)) answerAudioRefs.add(t.trim());
      }
    }
  }
  return QuestParseResult(rows, warnings, audioRefs, answerAudioRefs);
}

/// 依各難度把 [kQuiz2Ratio] 比例的題目（均勻散布）標成 area 2，其餘 area 1。
void assignAreas(List<QuestRow> rows, {double quiz2Ratio = kQuiz2Ratio}) {
  final byDiff = <int, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    byDiff.putIfAbsent(rows[i].difficulty, () => []).add(i);
  }
  for (final diff in byDiff.keys.toList()..sort()) {
    final idxs = byDiff[diff]!;
    final n = idxs.length;
    final k = (n * quiz2Ratio).round();
    final fight = <int>{};
    for (var j = 0; j < k; j++) {
      fight.add(((j + 0.5) * n / k).floor());
    }
    for (var pos = 0; pos < n; pos++) {
      rows[idxs[pos]].area = fight.contains(pos) ? kAreaFight : kAreaCollect;
    }
  }
}

/// 把一列轉成後端 QuestionInput payload。[resolveAudioUrl] 把音檔相對路徑換成已上傳的
/// URL（找不到時應自行丟出 [FormatException]）。
///
/// [resolveTranscript] 把「語音作答題答案欄的參考音檔」換成 STT 辨識文字（找不到時應自行
/// 丟出 [FormatException]）；未提供時，答案欄填音檔會直接丟 [FormatException]（呼叫端無
/// STT 連線）。格式不符時一律丟 [FormatException]。
Map<String, dynamic> buildQuestionPayload(
  QuestRow row,
  String Function(String value) resolveAudioUrl, {
  String Function(String audioPath)? resolveTranscript,
}) {
  // 敘述：音檔路徑 → audio，否則 text。
  final Map<String, dynamic> description = isAudioPath(row.prompt)
      ? {'type': 'audio', 'data': resolveAudioUrl(row.prompt)}
      : {'type': 'text', 'data': row.prompt};

  final nonempty = <(String, String)>[]; // (字母, 值)
  for (var i = 0; i < 4; i++) {
    if (row.options[i].isNotEmpty) nonempty.add((_letters[i], row.options[i]));
  }

  final Map<String, dynamic> content = {'description': description};
  final Map<String, dynamic> answer;

  if (nonempty.isEmpty) {
    // 語音作答題：答案是一個或多個可接受的「辨識文字」（以 | 分隔）。每一項可直接是文字，
    // 或是參考音檔（如 q1.wav）→ 經 [resolveTranscript] 轉成辨識文字。
    final tokens = splitAnswers(row.answer);
    if (tokens.isEmpty) {
      throw const FormatException('語音作答題（無選項）缺少答案');
    }
    final texts = <String>[];
    for (final t in tokens) {
      if (isAudioPath(t)) {
        if (resolveTranscript == null) {
          // 呼叫端沒有 STT 連線（例如未接後端時）；請改填辨識文字或走 seed 腳本。
          throw const FormatException(
              '語音作答題的答案音檔需經 STT 轉檔；請改填辨識文字或用 seed/seed_questions.py');
        }
        final text = resolveTranscript(t).trim();
        if (text.isEmpty) {
          throw FormatException('參考音檔「$t」辨識結果為空');
        }
        if (!texts.contains(text)) texts.add(text);
      } else if (!texts.contains(t)) {
        texts.add(t);
      }
    }
    answer = {'type': 'voice_response', 'data': texts};
  } else {
    // 選擇題：答案是一或多個字母（以 | 分隔）；選項若為音檔則以其 URL 當選項字串。
    final labels = [for (final (l, _) in nonempty) l];
    final tokens = splitAnswers(row.answer).map((t) => t.toUpperCase()).toList();
    if (tokens.isEmpty) {
      throw const FormatException('選擇題缺少答案');
    }
    final idxs = <int>[];
    for (final t in tokens) {
      final idx = labels.indexOf(t);
      if (idx < 0) {
        throw FormatException('答案「$t」不在現有選項 $labels 中');
      }
      if (!idxs.contains(idx)) idxs.add(idx);
    }
    content['choices'] = {
      'type': 'text',
      'data': [
        for (final (_, v) in nonempty) isAudioPath(v) ? resolveAudioUrl(v) : v,
      ],
    };
    answer = {'type': 'index', 'data': idxs};
  }

  return {
    'content': content,
    'answer': answer,
    'difficulty': row.difficulty,
    'area': row.area,
  };
}

/// 最小 CSV 解析（RFC4180 風格）：支援雙引號欄位、欄內逗號、跳脫引號("")、CRLF。
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else {
      switch (ch) {
        case '"':
          inQuotes = true;
        case ',':
          endField();
        case '\n':
          endRow();
        case '\r':
          break; // 併入 CRLF：忽略，交給 \n 收尾
        default:
          field.write(ch);
      }
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
