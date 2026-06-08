import 'dart:convert';

/// 一份「資訊文件」拆出來的單一分頁。
///
/// 撰寫格式為 Markdown，並以最上層標題 `# 標題` 切分頁：每個 `# 標題` 開一個分頁，
/// 標題文字即左側分頁標籤([tab])，其後到下一個 `# ` 之前的內容即該分頁的本文
/// ([markdown]，原樣交給 Markdown 元件渲染，支援 `##`、清單、**粗體**、圖片…）。
class InfoSection {
  /// 左側分頁標籤文字。
  final String tab;

  /// 此分頁的 Markdown 本文（不含開頭那行 `# 標題`）。
  final String markdown;

  const InfoSection({required this.tab, required this.markdown});
}

/// 將整份 Markdown 依最上層 `# 標題` 切成多個 [InfoSection]。
///
/// - 第一個 `# ` 之前若有內容，會獨立成一個分頁（標籤預設「簡介」）。
/// - 完全沒有 `# ` 時，整份視為單一分頁（標籤空字串，渲染端會隱藏分頁列）。
List<InfoSection> parseInfoSections(String raw) {
  final lines = const LineSplitter().convert(raw);
  final headingRe = RegExp(r'^#\s+(.+?)\s*$');

  final sections = <InfoSection>[];
  String? currentTab;
  final buf = <String>[];

  void flush() {
    final body = buf.join('\n').trim();
    // 第一個標題之前若沒有任何內容，不要生出空白分頁。
    if (currentTab == null && body.isEmpty) {
      buf.clear();
      return;
    }
    sections.add(InfoSection(tab: currentTab ?? '簡介', markdown: body));
    buf.clear();
  }

  for (final line in lines) {
    final m = headingRe.firstMatch(line);
    if (m != null) {
      flush();
      currentTab = m.group(1)!.trim();
    } else {
      buf.add(line);
    }
  }
  flush();

  // 完全沒有標題：整份當單一無標籤分頁。
  if (sections.isEmpty && raw.trim().isNotEmpty) {
    return [InfoSection(tab: '', markdown: raw.trim())];
  }
  return sections;
}
