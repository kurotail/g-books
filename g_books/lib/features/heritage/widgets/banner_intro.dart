import 'package:flutter/material.dart';

/// 橫幅進場動畫：黑色橫條淡入 → 主標題（金字）滑入 → 副標淡入 → 整條淡出。
/// 與「進入檢視古蹟」的進場動畫同款，供資源採集每回合開場重用。
///
/// 動畫播放一次，結束時呼叫 [onCompleted]。每回合以不同的 [key]（如 ValueKey(round)）
/// 重建即可重新播放。
class BannerIntro extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onCompleted;

  const BannerIntro({
    super.key,
    required this.title,
    this.subtitle,
    this.onCompleted,
  });

  @override
  State<BannerIntro> createState() => _BannerIntroState();
}

class _BannerIntroState extends State<BannerIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onCompleted?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _seg(double from, double to, double t) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value;
        // 橫條淡入(0-0.10) → 主標(0.12) → 副標(0.36) → 整條淡出(0.72-1.0)
        final bandAlpha = _seg(0.00, 0.10, t) * (1.0 - _seg(0.72, 1.00, t));
        final titleIn = _seg(0.12, 0.32, t);
        final titleSlide = (1.0 - _seg(0.12, 0.36, t)) * 28.0;
        final subIn = _seg(0.36, 0.52, t);
        final subtitle = widget.subtitle;

        return IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: bandAlpha.clamp(0.0, 1.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 46),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0x00000000),
                      Color(0xD9000000),
                      Color(0xD9000000),
                      Color(0x00000000),
                    ],
                    stops: [0.0, 0.16, 0.84, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: titleIn.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, titleSlide),
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFD4A843),
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 24,
                                offset: Offset(2, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Opacity(
                        opacity: subIn.clamp(0.0, 1.0),
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 22,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
