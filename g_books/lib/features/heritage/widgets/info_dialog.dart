import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../data/info_repository.dart';
import '../../../data/models/info_section.dart';

/// 全遊戲統一的「資訊框」：懸浮置中（約畫面 84%）、左側分頁標籤、右側為依序排列的
/// 文-圖-文（Markdown）。古蹟介紹與原料介紹共用同一個元件，差別只在原料會在最左側
/// 多帶一張卡圖（[leading]）。
///
/// 內容以 Markdown 撰寫，`# 標題` 分頁、`![說明](檔名){width=70}` 放圖（width 為內容欄
/// 寬度的百分比、未寫預設 70，高度自動等比）。圖片路徑自動以
/// `assets/heritages/<hid>/info_imgs/` 為前綴。
class InfoDialog extends StatelessWidget {
  final String heritageId;
  final String title;
  final Future<List<InfoSection>> sectionsFuture;

  /// 原料介紹時左側顯示的卡圖；古蹟介紹傳 null。
  final Widget? leading;

  const InfoDialog({
    super.key,
    required this.heritageId,
    required this.title,
    required this.sectionsFuture,
    this.leading,
  });

  /// 便捷：開啟某古蹟的介紹。
  static Future<void> showHeritage(
    BuildContext context, {
    required String heritageId,
    required String title,
  }) {
    return showDialog(
      context: context,
      builder: (_) => InfoDialog(
        heritageId: heritageId,
        title: title,
        sectionsFuture: InfoRepository.heritage(heritageId),
      ),
    );
  }

  /// 便捷：開啟某原料的介紹（左側帶卡圖）。
  static Future<void> showComponent(
    BuildContext context, {
    required String heritageId,
    required int componentId,
    required String title,
    required Widget leading,
  }) {
    return showDialog(
      context: context,
      builder: (_) => InfoDialog(
        heritageId: heritageId,
        title: title,
        leading: leading,
        sectionsFuture: InfoRepository.component(heritageId, componentId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: const Color(0xFF20242A),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x66D4A843)),
      ),
      child: SizedBox(
        width: screen.width * 0.84,
        height: screen.height * 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
          child: Column(
            children: [
              _header(context),
              const SizedBox(height: 6),
              const Divider(color: Color(0x33D4A843), height: 1),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<InfoSection>>(
                  future: sectionsFuture,
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFD4A843),
                        ),
                      );
                    }
                    final sections = snap.data ?? const [];
                    return _InfoBody(
                      heritageId: heritageId,
                      sections: sections,
                      leading: leading,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF3E7CE),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xCC3A3D42),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 內文：左側卡圖(可選) + 左側分頁列 + 右側 Markdown ───────────────────────────
class _InfoBody extends StatefulWidget {
  final String heritageId;
  final List<InfoSection> sections;
  final Widget? leading;

  const _InfoBody({
    required this.heritageId,
    required this.sections,
    this.leading,
  });

  @override
  State<_InfoBody> createState() => _InfoBodyState();
}

class _InfoBodyState extends State<_InfoBody> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    if (sections.isEmpty) {
      return const Center(
        child: Text(
          '資訊尚未開放，敬請期待。',
          style: TextStyle(color: Color(0xFF9C9384), fontSize: 16),
        ),
      );
    }
    final safeIndex = _index.clamp(0, sections.length - 1);
    // 只有一個分頁（且無標籤）時隱藏分頁列。
    final showTabs = sections.length > 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.leading != null) ...[
          SizedBox(width: 240, child: Center(child: widget.leading)),
          const SizedBox(width: 24),
        ],
        if (showTabs) ...[
          _tabRail(sections, safeIndex),
          const SizedBox(width: 18),
        ],
        Expanded(child: _content(sections[safeIndex])),
      ],
    );
  }

  Widget _tabRail(List<InfoSection> sections, int active) {
    return SizedBox(
      width: 132,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final on = i == active;
          return GestureDetector(
            onTap: () => setState(() => _index = i),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: on ? const Color(0x22D4A843) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: on ? const Color(0xFFD4A843) : Colors.white12,
                    width: on ? 4 : 2,
                  ),
                ),
              ),
              child: Text(
                sections[i].tab,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: on ? const Color(0xFFF3E7CE) : Colors.white60,
                  fontSize: 16,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(InfoSection section) {
    return Markdown(
      key: ValueKey(section.tab),
      data: _prepImages(section.markdown),
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      imageBuilder: _imageBuilder,
      styleSheet: _styleSheet,
    );
  }

  /// 圖片寬度語法 `{width=NN}` 轉成 Markdown 標準 title 帶過去（`![alt](src "NN")`），
  /// 沒寫寬度的也補上預設 70，供 [_imageBuilder] 讀取。
  static final _imgRe = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)(?:\{width=(\d+)\})?');

  String _prepImages(String md) {
    return md.replaceAllMapped(_imgRe, (m) {
      final alt = m.group(1) ?? '';
      final src = m.group(2)!;
      final w = m.group(3) ?? '70';
      return '![$alt]($src "$w")';
    });
  }

  Widget _imageBuilder(Uri uri, String? title, String? alt) {
    final pct = (int.tryParse(title ?? '') ?? 70).clamp(10, 100);
    final assetPath = '${InfoRepository.imageBaseDir(widget.heritageId)}$uri';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (_, c) {
          final base = c.maxWidth.isFinite ? c.maxWidth : 420.0;
          final w = base * pct / 100;
          return Align(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    assetPath,
                    width: w,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (_, _, _) => _imgPlaceholder(w),
                  ),
                ),
                if (alt != null && alt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: w,
                    child: Text(
                      alt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9C9384),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _imgPlaceholder(double w) {
    return Container(
      width: w,
      height: w * 0.56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3D40), Color(0xFF24272A)],
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24, size: 38),
      ),
    );
  }

  static final _styleSheet = MarkdownStyleSheet(
    p: const TextStyle(
      color: Color(0xFFE9E3D8),
      fontSize: 18,
      height: 1.95,
      letterSpacing: 0.4,
    ),
    h1: const TextStyle(
      color: Color(0xFFD4A843),
      fontSize: 26,
      fontWeight: FontWeight.w800,
      height: 1.8,
    ),
    h2: const TextStyle(
      color: Color(0xFFD4A843),
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.8,
    ),
    h3: const TextStyle(
      color: Color(0xFFE3C77A),
      fontSize: 19,
      fontWeight: FontWeight.w700,
      height: 1.6,
    ),
    strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    em: const TextStyle(
      color: Color(0xFFE9E3D8),
      fontStyle: FontStyle.italic,
    ),
    listBullet: const TextStyle(
      color: Color(0xFFE9E3D8),
      fontSize: 18,
      height: 1.95,
    ),
    a: const TextStyle(
      color: Color(0xFFD4A843),
      decoration: TextDecoration.underline,
    ),
    blockquote: const TextStyle(
      color: Color(0xFFB8AE98),
      fontSize: 17,
      height: 1.8,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0x22000000),
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: Color(0xFFD4A843), width: 3),
      ),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x33D4A843), width: 1)),
    ),
  );
}
