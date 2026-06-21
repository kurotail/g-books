import 'dart:async';
import 'api_client.dart';

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

/// 一道題目。對應後端 generate / target 回傳：
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

/// 作答內容。對應後端 `POST /api/question/answer`：
/// 選擇題 `{session, answer: <index>}`；語音題 `{session, answer: "<wav base64>"}`。
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

  /// 後端 `answer` 欄位：選擇題為數字、語音題為 base64 字串。
  Object get payload => choiceIndex ?? audioBase64 ?? 0;
}

/// 作答結果（對應後端 `AnswerResponse`）。
/// [itemId] 在「採集答對、後端入庫」時帶回（前端據此查背包顯示獲得的原料）；
/// mock 不走伺服器入庫，[itemId] 為 null（由前端自行發獎）。
class QuizResult {
  final bool correct;
  final int? itemId;
  const QuizResult({required this.correct, this.itemId});
}

/// 題目來源抽象層。對應後端：
///   - [fetchQuestion] ↔ `POST /api/question/generate`（依難度取題，順帶在伺服器
///     建立待領取的物品與 session；答案不外洩）
///   - [submitAnswer]  ↔ `POST /api/question/answer`（送出作答 → 回正確與否、
///     及答對時入庫的 item_id）
///
/// 之後換真後端只要在 `main.dart` 換成 [ApiQuizService]，前端與 UI 不需更動。
abstract class QuizService {
  /// 依 [difficulty]（1=易 / 2=中 / 3=難）取一題。[heritageId] 供 mock 決定原料池；
  /// API 模式下後端依 token 的 group→building 自行決定，不需用到。
  Future<QuizQuestion> fetchQuestion({
    required String heritageId,
    required int difficulty,
  });

  Future<QuizResult> submitAnswer(QuizAnswer answer);
}

/// 本機 mock：輪播四種題型（文字＋文字選擇 / 語音敘述＋文字選擇 / 文字＋語音選擇 /
/// 文字＋語音作答），確保每種作答介面都能測到；難度只影響採集獎勵等級，不影響題型。
/// 正確選項以 session 暫存
/// 供 [submitAnswer] 比對；語音作答因本機無法判定，一律視為正確（之後由後端判定）。
/// mock 不回 item_id（採集獎勵由前端 [grantRandomOfLevel] 發），與後端 DTO 相容。
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
    final kind = _seq % 4;
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
      case 2: // 文字題 + 語音選擇題（選項是音檔，播放後選正確念法）
        _correctBySession[session] = 1;
        return QuizQuestion(
          session: session,
          prompt: const QuizPrompt(
            type: QuizMediaType.text,
            data: '下列哪個是「媽祖」的正確台語念法？請播放各選項後選出。',
          ),
          choices: const QuizChoices(
            // mock 選項音檔 url：本機無對應檔，播放會優雅失敗（toast 提示），
            // 之後由後端提供真實 /audio url。
            data: [
              '/audio/mock_choice_a.mp3',
              '/audio/mock_choice_b.mp3',
              '/audio/mock_choice_c.mp3',
              '/audio/mock_choice_d.mp3',
            ],
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

/// 後端實作：取題走 `POST /api/question/generate`、作答走 `POST /api/question/answer`。
/// 答對且為採集（KindItem）時回傳 `item_id`，前端據此刷新背包並顯示獲得的原料。
class ApiQuizService implements QuizService {
  ApiQuizService(this._client);

  final ApiClient _client;

  @override
  Future<QuizQuestion> fetchQuestion({
    required String heritageId,
    required int difficulty,
  }) async {
    final m = await _client.sendJson('POST', '/api/question/generate',
        body: {'difficulty': difficulty}) as Map<String, dynamic>;
    return _parseQuestion(m);
  }

  @override
  Future<QuizResult> submitAnswer(QuizAnswer answer) async {
    final m = await _client.sendJson('POST', '/api/question/answer', body: {
      'session': answer.session,
      'answer': answer.payload,
    }) as Map<String, dynamic>;
    final itemId = (m['item_id'] as num?)?.toInt();
    return QuizResult(
      correct: m['correct'] == true,
      itemId: (itemId != null && itemId != 0) ? itemId : null,
    );
  }

  QuizQuestion _parseQuestion(Map<String, dynamic> m) {
    final content = m['content'] as Map<String, dynamic>;
    final desc = content['description'] as Map<String, dynamic>;
    final choicesRaw = content['choices'] as Map<String, dynamic>?;
    return QuizQuestion(
      session: m['session'] as String,
      prompt: QuizPrompt(
        type: _mediaType(desc['type'] as String?),
        data: (desc['data'] as String?) ?? '',
      ),
      choices: choicesRaw == null
          ? null
          : QuizChoices(
              data: [
                for (final c in (choicesRaw['data'] as List? ?? const []))
                  c as String,
              ],
            ),
    );
  }

  /// 後端 description.type：`text` / `audio` / `voice_response`。
  /// `voice_response` 是「語音作答」題，敘述本身仍可能是文字或音檔；這裡只決定
  /// 敘述要不要當音檔播放（audio→播放，其餘→文字）。是否為語音作答由 choices 是否
  /// 存在決定（後端對 voice_response 題不給 choices）。
  static QuizMediaType _mediaType(String? t) =>
      t == 'audio' ? QuizMediaType.audio : QuizMediaType.text;
}
