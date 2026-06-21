import 'package:flutter_test/flutter_test.dart';
import 'package:g_books/services/question_import.dart';

/// 測試用：把音檔相對路徑換成可預期的假 URL。
String fakeUrl(String v) => '/audio/U_${v.trim()}';

void main() {
  group('parseQuestCsv', () {
    test('跳過欄名列、回傳資料列與音檔引用', () {
      final r = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n'
        '神明是誰,王爺,媽祖,土地公,關公,B,1\n'
        '請說台語,,,,,q1.wav,2\n'
        '哪個念法,a.wav,b.wav,,,A,3\n',
      );
      expect(r.rows.length, 3);
      expect(r.rows[0].difficulty, 1);
      expect(r.audioRefs, {'q1.wav', 'a.wav', 'b.wav'});
      expect(r.warnings, isEmpty);
    });

    test('容許 BOM、CRLF 與引號內逗號', () {
      final r = parseQuestCsv(
        '﻿題目,A,B,C,D,答案,難度\r\n'
        '"問句, 含逗號",甲,乙,,,A,1\r\n',
      );
      expect(r.rows.length, 1);
      expect(r.rows.single.prompt, '問句, 含逗號');
      expect(r.rows.single.options[0], '甲');
    });

    test('難度非數字或題目為空 → 記為警告並略過', () {
      final r = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n'
        '壞題,甲,乙,,,A,難\n'
        ',甲,乙,,,A,1\n',
      );
      expect(r.rows, isEmpty);
      expect(r.warnings.length, 2);
    });
  });

  group('buildQuestionPayload', () {
    test('一般選擇題：文字選項 + index 答案（去除空白選項）', () {
      final row = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n神明是誰,王爺,媽祖,土地公,,B,1\n',
      ).rows.single;
      final p = buildQuestionPayload(row, fakeUrl);
      expect(p['content']['description'], {'type': 'text', 'data': '神明是誰'});
      expect(p['content']['choices'], {
        'type': 'text',
        'data': ['王爺', '媽祖', '土地公'],
      });
      expect(p['answer'], {'type': 'index', 'data': 1});
    });

    test('語音選項題：選項換成音檔 URL，答案仍是 index', () {
      final row = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n哪個念法,A.wav,B.wav,C.wav,D.wav,C,2\n',
      ).rows.single;
      final p = buildQuestionPayload(row, fakeUrl);
      expect(p['content']['choices']['data'], [
        '/audio/U_A.wav',
        '/audio/U_B.wav',
        '/audio/U_C.wav',
        '/audio/U_D.wav',
      ]);
      expect(p['answer'], {'type': 'index', 'data': 2});
    });

    test('語音作答題：無選項、答案是參考音檔 URL', () {
      final row = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n請說台語,,,,,q1.wav,1\n',
      ).rows.single;
      final p = buildQuestionPayload(row, fakeUrl);
      expect(p['content'].containsKey('choices'), isFalse);
      expect(p['answer'], {'type': 'voice_response', 'data': '/audio/U_q1.wav'});
    });

    test('語音敘述題：題目欄是音檔 → description.type=audio', () {
      final row = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\nclip.mp3,甲,乙,,,A,1\n',
      ).rows.single;
      final p = buildQuestionPayload(row, fakeUrl);
      expect(p['content']['description'], {
        'type': 'audio',
        'data': '/audio/U_clip.mp3',
      });
    });

    test('答案字母不在選項中 → 丟 FormatException', () {
      final row = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n題,甲,乙,,,D,1\n',
      ).rows.single;
      expect(() => buildQuestionPayload(row, fakeUrl), throwsFormatException);
    });
  });

  group('assignAreas', () {
    test('各難度約 25% 進攻防戰、其餘採集', () {
      final rows = parseQuestCsv(
        '題目,A,B,C,D,答案,難度\n' +
            List.generate(
              20,
              (i) => '題$i,甲,乙,,,A,1',
            ).join('\n') +
            '\n',
      ).rows;
      assignAreas(rows);
      final fight = rows.where((r) => r.area == kAreaFight).length;
      final collect = rows.where((r) => r.area == kAreaCollect).length;
      expect(fight, 5); // round(20 * 0.25)
      expect(collect, 15);
    });
  });
}
