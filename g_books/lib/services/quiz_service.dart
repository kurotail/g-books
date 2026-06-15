import 'dart:async';

/// 題目內容型別：文字或語音。
enum QuizMediaType { text, audio }

/// 題目敘述（對應後端 `content.description`）。
/// - [QuizMediaType.text]：[data] 為題目文字。
/// - [QuizMediaType.audio]：[data] 為音檔 url（前端播放）。
class QuizPrompt {
  final QuizMediaType type;
  final String data;
  const QuizPrompt({required this.type, required this.data});

  bool get isAudio => type == QuizMediaType.audio;
}

/// 選項（對應後端 `content.choices`）。目前僅文字選項；
/// 整題 `choices == null` 代表此題為「語音作答」（無選項、改錄音）。
class QuizChoices {
  final QuizMediaType type; // 目前固定 text
  final List<String> data;
  const QuizChoices({this.type = QuizMediaType.text, required this.data});
}

/// 一道題目。對應後端回傳：
/// `{ "session": "...", "content": { "description": {...}, "choices": {...}? } }`
class QuizQuestion {
  final String session;
  final QuizPrompt prompt; // content.description
  final QuizChoices? choices; // content.choices（null → 語音作答）

  const QuizQuestion({
    required this.session,
    required this.prompt,
    this.choices,
  });

  /// 有選項 → 選擇題；無選項 → 語音作答。
  bool get isChoice => choices != null;
}

/// 作答內容。對應後端：選擇題回 `{session, answer: <index>}`；
/// 語音題回 `{session, answer: "<wav base64>"}`。
class QuizAnswer {
  final String session;
  final int? choiceIndex;
  final String? audioBase64;

  const QuizAnswer.choice(this.session, int index)
      : choiceIndex = index,
        audioBase64 = null;

  const QuizAnswer.audio(this.session, String base64)
      : audioBase64 = base64,
        choiceIndex = null;
}

/// 作答結果（後端判定正確與否）。
class QuizResult {
  final bool correct;
  const QuizResult({required this.correct});
}

/// 題目來源抽象層。對應後端：
///   - [fetchQuestion] ↔ 依難度取題（回傳上述 question 格式）
///   - [submitAnswer]  ↔ 送出作答（`{session, answer}`）→ 回正確與否
///
/// 之後換真後端只要新增 `ApiQuizService implements QuizService` 並在 `main.dart`
/// 換掉實作，前端與 UI 不需更動。
abstract class QuizService {
  /// 依 [difficulty]（1=易 / 2=中 / 3=難）取一題。
  Future<QuizQuestion> fetchQuestion({
    required String heritageId,
    required int difficulty,
  });

  Future<QuizResult> submitAnswer(QuizAnswer answer);
}

/// 本機 mock：輪播三種題型（文字＋選擇 / 語音＋選擇 / 文字＋語音作答），確保每種
/// 作答介面都能測到；難度只影響採集獎勵等級，不影響題型。正確選項以 session 暫存
/// 供 [submitAnswer] 比對；語音作答因本機無法判定，一律視為正確（之後由後端判定）。
class MockQuizService implements QuizService {
  static const _netDelay = Duration(milliseconds: 350);
  int _seq = 0;
  final Map<String, int> _correctBySession = {};

  @override
  Future<QuizQuestion> fetchQuestion({
    required String heritageId,
    required int difficulty,
  }) async {
    await Future<void>.delayed(_netDelay);
    final session =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}_$_seq';
    final kind = _seq % 3;
    _seq++;

    switch (kind) {
      case 0: // 文字題 + 文字選擇題
        _correctBySession[session] = 3;
        return QuizQuestion(
          session: session,
          prompt: const QuizPrompt(
            type: QuizMediaType.text,
            data: '北港朝天宮建築上常見龍、鳳凰等裝飾，這些圖案最主要代表什麼？',
          ),
          choices: const QuizChoices(
            data: ['美觀而已', '記錄歷史事件', '表示神明的寵物坐騎', '吉祥與祈福'],
          ),
        );
      case 1: // 語音題 + 文字選擇題
        _correctBySession[session] = 0;
        return QuizQuestion(
          session: session,
          prompt: QuizPrompt(
            type: QuizMediaType.audio,
            // mock 音檔 url：本機無對應檔，播放會優雅失敗（toast 提示），
            // 之後由後端提供真實 url。
            data: 'https://example.com/mock/quiz_$difficulty.mp3',
          ),
          choices: const QuizChoices(
            data: ['媽祖', '關聖帝君', '土地公', '保生大帝'],
          ),
        );
      default: // 文字題 + 語音作答（錄音）
        return QuizQuestion(
          session: session,
          prompt: const QuizPrompt(
            type: QuizMediaType.text,
            data: '請用台語唸出【笨港】？',
          ),
          choices: null,
        );
    }
  }

  @override
  Future<QuizResult> submitAnswer(QuizAnswer answer) async {
    await Future<void>.delayed(_netDelay);
    if (answer.audioBase64 != null) {
      // 語音作答：mock 無法驗證，視為正確（之後由後端判定）。
      return const QuizResult(correct: true);
    }
    final correct = _correctBySession[answer.session];
    return QuizResult(
      correct: correct != null && answer.choiceIndex == correct,
    );
  }
}
