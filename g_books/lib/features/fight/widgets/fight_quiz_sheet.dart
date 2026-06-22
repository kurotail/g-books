import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../services/api_client.dart' show resolveMediaUrl;
import '../../../services/question_import.dart' show isAudioPath;
import '../../../services/quiz_service.dart';

/// 攻防戰（QUIZ2）作答覆蓋層：對一道已取得的 [QuizQuestion]（由
/// `targetQuestion` 開的攻擊 / 修復 session）作答。作答介面與資源採集一致
/// （文字 / 語音題敘述、文字 / 語音選項、語音錄音作答），但去掉回合與獎勵。
///
/// 一旦進來代表已開好 target session（已對該格下注），故作答中不可離開，必須答完。
///   - 送出成功 → [onResult]（父層據 [QuizResult.success] 顯示攻破 / 修復成功或失敗）。
///   - 送出失敗（連線 / session 逾時 400）→ [onAbort]（父層收掉並提示重來）。
class FightQuizSheet extends StatefulWidget {
  const FightQuizSheet({
    super.key,
    required this.question,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onSubmit,
    required this.onResult,
    required this.onAbort,
  });

  final QuizQuestion question;

  /// 標題（攻擊：「攻打 XX隊」；修復：「修復古蹟」）。
  final String title;

  /// 副標（目標元件名稱）。
  final String subtitle;

  /// 強調色（攻擊偏紅、修復偏綠），用於頂部標籤。
  final Color accent;

  /// 送出作答 → 後端判定（父層提供，內部走 `QuizService.submitAnswer`）。
  final Future<QuizResult> Function(QuizAnswer answer) onSubmit;

  /// 送出成功並取得結果。
  final void Function(QuizResult result) onResult;

  /// 送出失敗（例外）→ 由父層收掉此覆蓋層並提示。
  final VoidCallback onAbort;

  @override
  State<FightQuizSheet> createState() => _FightQuizSheetState();
}

class _FightQuizSheetState extends State<FightQuizSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _playCompleteSub;

  int? _selected; // 選擇題選中的選項
  bool _submitting = false;
  bool _recording = false;
  String? _recordedPath;
  String? _playingId; // 'prompt' / 'choice:<i>' / 'clip'；null = 沒在播

  QuizQuestion get _q => widget.question;

  @override
  void initState() {
    super.initState();
    _playCompleteSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _playCompleteSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── 送出 ────────────────────────────────────────────────────────────────────
  Future<void> _submitChoice() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await widget.onSubmit(QuizAnswer.choice(_q.session, _selected!));
      if (!mounted) return;
      widget.onResult(res);
    } catch (_) {
      _fail();
    }
  }

  Future<void> _submitAudio() async {
    final path = _recordedPath;
    if (path == null || _submitting) return;
    setState(() => _submitting = true);
    String b64;
    try {
      b64 = base64Encode(await File(path).readAsBytes());
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('讀取錄音失敗');
      return;
    }
    try {
      final res = await widget.onSubmit(QuizAnswer.audio(_q.session, b64));
      if (!mounted) return;
      widget.onResult(res);
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onAbort();
  }

  // ── 語音錄音 / 播放 ──────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('需要麥克風權限才能錄音');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/fight_answer_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav),
          path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordedPath = null;
      });
    } catch (_) {
      if (mounted) _toast('無法開始錄音');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordedPath = path;
      });
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _reRecord() async {
    await _stopPlay();
    if (!mounted) return;
    setState(() => _recordedPath = null);
  }

  Future<void> _startPlay(String id, Source source, String errMsg) async {
    try {
      await _player.stop();
      if (!mounted) return;
      setState(() => _playingId = id);
      await _player.play(source);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
      _toast(errMsg);
    }
  }

  Future<void> _stopPlay() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (mounted) setState(() => _playingId = null);
  }

  Future<void> _togglePlay(String id, Source source, String errMsg) async {
    if (_playingId == id) {
      await _stopPlay();
    } else {
      await _startPlay(id, source, errMsg);
    }
  }

  void _toast(String msg) =>
      Fluttertoast.showToast(msg: msg, gravity: ToastGravity.CENTER);

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 攔截返回鍵：作答中不可離開。
    return PopScope(
      canPop: false,
      child: ColoredBox(
        color: const Color(0xF015110C),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(child: Center(child: _promptArea(_q))),
              _answerPanel(_q),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.accent),
            ),
            child: Text(
              widget.title,
              style: TextStyle(
                color: widget.accent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _promptArea(QuizQuestion q) {
    if (q.prompt.isAudio) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('請聆聽題目後作答',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => _startPlay(
              'prompt',
              UrlSource(resolveMediaUrl(q.prompt.data) ?? q.prompt.data),
              '語音載入失敗（mock 無音檔）',
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xF0241F19),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFD4A843)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_up_rounded,
                      color: Color(0xFFD4A843), size: 24),
                  SizedBox(width: 10),
                  Text('播放語音題目',
                      style: TextStyle(
                          color: Color(0xFFE8DCC0),
                          fontSize: 18,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        q.prompt.data,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          height: 1.5,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 12, offset: Offset(1, 2)),
          ],
        ),
      ),
    );
  }

  Widget _answerPanel(QuizQuestion q) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: const BoxDecoration(
        color: Color(0xF2CDB590),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: q.isChoice ? _choicePanel(q.choices!.data) : _recordPanel(),
      ),
    );
  }

  Widget _choicePanel(List<String> choices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          () {
            final raw = choices[i];
            final audio = isAudioPath(raw);
            final url = audio ? (resolveMediaUrl(raw) ?? raw) : null;
            return _ChoiceTile(
              index: i,
              text: audio ? '選項 ${i + 1}' : raw,
              audioUrl: url,
              selected: _selected == i,
              playing: _playingId == 'choice:$i',
              onTap: _submitting ? null : () => setState(() => _selected = i),
              onPlay: url == null
                  ? null
                  : () => _togglePlay('choice:$i', UrlSource(url),
                      '語音載入失敗（mock 無音檔）'),
            );
          }(),
        ],
        const SizedBox(height: 18),
        Center(
          child: _panelAction(
            label: '確 認',
            enabled: _selected != null && !_submitting,
            onTap: _submitChoice,
          ),
        ),
      ],
    );
  }

  Widget _recordPanel() {
    final hasClip = _recordedPath != null && !_recording;
    final clipPlaying = _playingId == 'clip';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => _startRecording(),
          onTapUp: (_) => _stopRecording(),
          onTapCancel: _stopRecording,
          child: _MicButton(recording: _recording),
        ),
        const SizedBox(height: 12),
        Text(
          _recording
              ? '錄音中…放開即停止'
              : (hasClip ? '已錄好，可試聽或送出' : '按壓麥克風，並說出你的答案'),
          style: const TextStyle(
              color: Color(0xFF4A3A28),
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasClip) ...[
              _smallPill(
                icon: clipPlaying
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                label: clipPlaying ? '停止' : '試聽',
                onTap: () => _togglePlay(
                    'clip', DeviceFileSource(_recordedPath!), '無法播放錄音'),
              ),
              const SizedBox(width: 14),
              _smallPill(
                icon: Icons.refresh_rounded,
                label: '重錄',
                onTap: _submitting ? null : _reRecord,
              ),
              const SizedBox(width: 14),
            ],
            _panelAction(
              label: '送 出',
              enabled: hasClip && !_submitting,
              onTap: _submitAudio,
            ),
          ],
        ),
      ],
    );
  }

  Widget _panelAction({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF241F19),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFD4A843), width: 1.4),
          ),
          child: _submitting && enabled
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Color(0xFFD4A843)),
                )
              : Text(label,
                  style: const TextStyle(
                      color: Color(0xFFE8DCC0),
                      fontSize: 18,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x33241F19),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF8A6A40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(icon,
                  key: ValueKey(icon), color: const Color(0xFF4A3A28), size: 20),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF4A3A28),
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── 選擇題選項（與資源採集相同樣式）─────────────────────────────────────────────
class _ChoiceTile extends StatelessWidget {
  final int index;
  final String text;
  final String? audioUrl;
  final bool selected;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  const _ChoiceTile({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
    this.audioUrl,
    this.playing = false,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isAudio = audioUrl != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF241F19),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? const Color(0xFFD4A843) : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFD4A843)
                    : const Color(0x33FFFFFF),
                shape: BoxShape.circle,
              ),
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: selected ? const Color(0xFF2A1A0A) : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFFF0E8D8),
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ),
            if (isAudio) ...[
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPlay,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: playing
                        ? const Color(0xFFD4A843)
                        : const Color(0x33D4A843),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD4A843)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                      color: playing
                          ? const Color(0xFF2A1A0A)
                          : const Color(0xFFD4A843),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 麥克風按鈕（與資源採集相同樣式）────────────────────────────────────────────
class _MicButton extends StatelessWidget {
  final bool recording;
  const _MicButton({required this.recording});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: recording ? 96 : 86,
      height: recording ? 96 : 86,
      decoration: BoxDecoration(
        color: recording ? const Color(0xFFFF6B5E) : const Color(0xFF241F19),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD4A843), width: 2),
        boxShadow: [
          if (recording)
            const BoxShadow(
                color: Color(0x66FF6B5E), blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Icon(
        recording ? Icons.mic : Icons.mic_none_rounded,
        color: recording ? Colors.white : const Color(0xFFD4A843),
        size: 40,
      ),
    );
  }
}
