import 'package:flutter/material.dart';

// 1. 古蹟資料模型 (保持不變)
class HistoricSite {
  final String name;
  final String description;
  final String imagePath;

  HistoricSite({
    required this.name,
    required this.description,
    required this.imagePath,
  });
}

// 2. 自定義元件：處理 Overlay 提示框
class OverlaySiteSelectionWidget extends StatefulWidget {
  final Widget child; // 你的 GridView 放這裡
  final Widget Function(HistoricSite site, Offset offset, Size size) tooltipBuilder; // 提示框的生成器

  const OverlaySiteSelectionWidget({
    Key? key,
    required this.child,
    required this.tooltipBuilder,
  }) : super(key: key);

  @override
  State<OverlaySiteSelectionWidget> createState() => _OverlaySiteSelectionWidgetState();
}

class _OverlaySiteSelectionWidgetState extends State<OverlaySiteSelectionWidget> {
  // 用於控制 OverlayEntry 的顯示與隱藏
  OverlayEntry? _tooltipOverlayEntry;

  // 隱藏提示框的方法
  void hideTooltip() {
    _tooltipOverlayEntry?.remove();
    _tooltipOverlayEntry = null;
  }

  // 顯示提示框的方法
  void showTooltip(HistoricSite site, Offset imagePosition, Size imageSize) {
    hideTooltip(); // 確保同時只有一個提示框

    // 建立一個 OverlayEntry
    _tooltipOverlayEntry = OverlayEntry(
      builder: (context) {
        // 使用 Stack 在 Overaly 層中定位提示框
        return Material(
          color: Colors.transparent, // Overaly 本身背景透明
          child: Stack(
            children: [
              // 一個透明的 Listener，用於點擊畫面任意處隱藏提示框 (可選，這裡主要靠 MouseRegion 移出)
              GestureDetector(
                onTap: hideTooltip,
                child: Container(color: Colors.transparent),
              ),
              // 調用外部傳入的 tooltipBuilder 來生成提示框 Widget，並傳入圖片的位置和大小供定位使用
              widget.tooltipBuilder(site, imagePosition, imageSize),
            ],
          ),
        );
      },
    );

    // 將 OverlayEntry 加入到 Overaly 中
    Overlay.of(context).insert(_tooltipOverlayEntry!);
  }

  @override
  void dispose() {
    // 元件銷毀時確保移除 Overlay
    hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 這個 Widget 只負責包覆 child，並提供顯示/隱藏 Overlay 的功能
    return widget.child;
  }

  // 靜態方法，方便 child 元件調用
  static _OverlaySiteSelectionWidgetState? of(BuildContext context) {
    return context.findAncestorStateOfType<_OverlaySiteSelectionWidgetState>();
  }
}

// 3. 單一古蹟元件：偵測 MouseRegion 並呼叫 Overlay
class SiteItemWithTooltip extends StatefulWidget {
  final HistoricSite site;
  final Widget child;

  const SiteItemWithTooltip({
    Key? key,
    required this.site,
    required this.child,
  }) : super(key: key);

  @override
  State<SiteItemWithTooltip> createState() => _SiteItemWithTooltipState();
}

class _SiteItemWithTooltipState extends State<SiteItemWithTooltip> {
  // 為每個圖片元件分配一個唯一的 Key
  final GlobalKey _imageKey = GlobalKey();

  // 計算元件在畫面上的位置和大小
  Offset? _getImagePosition() {
    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.localToGlobal(Offset.zero);
  }

  Size? _getImageSize() {
    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        // 滑鼠進入：獲取位置和大小，顯示 Overlay
        final position = _getImagePosition();
        final size = _getImageSize();
        if (position != null && size != null) {
          _OverlaySiteSelectionWidgetState.of(context)?.showTooltip(widget.site, position, size);
        }
      },
      onExit: (_) {
        // 滑鼠移出：隱藏 Overlay
        _OverlaySiteSelectionWidgetState.of(context)?.hideTooltip();
      },
      // 將 GlobalKey 綁定到具體的圖片 Container 上
      child: Container(
        key: _imageKey,
        child: widget.child,
      ),
    );
  }
}

// 4. 主介面 (SelectSiteScreen) 與 GridView 實作 (保持不變)
class SelectSiteScreen extends StatefulWidget {
  const SelectSiteScreen({Key? key}) : super(key: key);

  @override
  State<SelectSiteScreen> createState() => _SelectSiteScreenState();
}

class _SelectSiteScreenState extends State<SelectSiteScreen> {
  // 模擬的古蹟資料 (保持不變)
  final List<HistoricSite> sites = [
    HistoricSite(
      name: '安平古堡',
      description: '建於1624年，是台灣最早的要塞建築。這是一段關於這座美麗古蹟的歷史文化敘事介紹。',
      imagePath: 'assets/site_1.png',
    ),
    HistoricSite(
      name: '北港朝天宮',
      description: '北港朝天宮在日治時期有「臺灣媽祖信仰總本山」之稱，南來北往的進香團絡繹不絕，形成了特有進香文化，更帶動了地方的經濟發展。這是一段關於這座美麗古蹟的歷史文化敘事介紹。',
      imagePath: 'assets/site_2.png',
    ),
    HistoricSite(
      name: '安平樹屋',
      description: '原為德記洋行倉庫，現已被榕樹氣根與枝幹攀附。這是一段關於這座美麗古蹟的歷史文化敘事介紹。',
      imagePath: 'assets/site_3.png',
    ),
    ...List.generate(6, (index) => HistoricSite(
      name: '歷史建築 ${index + 4}',
      description: '這是一段關於這座美麗古蹟的歷史文化敘事介紹。',
      imagePath: 'assets/site_placeholder.png',
    )),
  ];

  @override
  Widget build(BuildContext context) {
    // 獲取畫面高度，用於網格佈局
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFB9A689), // 仿舊紙張/沙土底色
      // 使用自定義的 OverlaySiteSelectionWidget 包覆整個內容
      body: OverlaySiteSelectionWidget(
        // 定義如何生成提示框 (ToolTip)
        tooltipBuilder: (site, imagePosition, imageSize) {
          // 在這裡計算提示框相對於圖片的位置
          // 範例：將提示框定位在圖片的「右上方」
          return Positioned(
            left: imagePosition.dx + imageSize.width + 10, // 圖片右側 10px
            top: imagePosition.dy - 50, // 圖片上方 50px (可根據提示框高度調整)
            child: _buildHoverTooltip(site),
          );
        },
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // 頂部標題按鈕 (保持不變)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '選擇古蹟',
                  style: TextStyle(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4.0,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // 分隔線與副標題 (保持不變)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 60, height: 2, color: Colors.black87),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      '請選擇一座古蹟進行遊戲',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(width: 60, height: 2, color: Colors.black87),
                ],
              ),
              const SizedBox(height: 40),

              // 3x3 古蹟網格
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(), // 關閉滾動
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.75, // 調整圖片與按鈕的比例
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: sites.length,
                    itemBuilder: (context, index) {
                      // 使用 SiteItemWithTooltip 包覆每一個網格項
                      return SiteItemWithTooltip(
                        site: sites[index],
                        // 單一古蹟的 UI 元件
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black45, width: 1),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  )
                                ],
                                image: DecorationImage(
                                  // 建議將你的 Figma 古蹟圖片匯出放入 assets
                                  image: AssetImage(sites[index].imagePath),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 選擇按鈕
                            Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B4A45),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black, width: 1.5),
                              ),
                              child: const Center(
                                child: Text(
                                  '選擇',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 構建懸浮資訊框 (Frame 5 的樣式，保持不變)
  Widget _buildHoverTooltip(HistoricSite site) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFDEB586), // 淺棕色背景
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(4, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            site.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            site.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.black87,
            ),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }
}