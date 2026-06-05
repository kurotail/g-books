import 'package:flutter/material.dart';

// 1. 定義燈泡景點的資料結構
class SpotInfo {
  final double xPercent; // 燈泡的 X 軸相對位置 (0.0 左邊 ~ 1.0 右邊)
  final double yPercent; // 燈泡的 Y 軸相對位置 (0.0 上方 ~ 1.0 下方)
  final String title;    // 提示框標題
  final String content;  // 提示框內容

  SpotInfo({
    required this.xPercent,
    required this.yPercent,
    required this.title,
    required this.content,
  });
}

class TempleMapScreen extends StatefulWidget {
  const TempleMapScreen({Key? key}) : super(key: key);

  @override
  State<TempleMapScreen> createState() => _TempleMapScreenState();
}

class _TempleMapScreenState extends State<TempleMapScreen> {
  // 當前被鼠標懸浮的景點
  SpotInfo? _hoveredSpot;
  Offset _mousePosition = Offset.zero;

  // ==========================================
  // 👇👇👇 請在這裡填寫你的燈泡資訊 👇👇👇
  // ==========================================
  final List<SpotInfo> spots = [
    SpotInfo(
      xPercent: 0.50, yPercent: 0.25, // 頂層主殿
      title: '【填空：建築名稱 1】',
      content: '【填空：請在此輸入關於這個位置的歷史文化介紹或遊戲提示...】',
    ),
    SpotInfo(
      xPercent: 0.35, yPercent: 0.45, // 左側偏殿
      title: '【填空：建築名稱 2】',
      content: '【填空：請在此輸入關於這個位置的歷史文化介紹或遊戲提示...】',
    ),
    SpotInfo(
      xPercent: 0.65, yPercent: 0.45, // 右側偏殿
      title: '【填空：建築名稱 3】',
      content: '【填空：請在此輸入關於這個位置的歷史文化介紹或遊戲提示...】',
    ),
    SpotInfo(
      xPercent: 0.50, yPercent: 0.60, // 前殿/三川殿
      title: '【填空：建築名稱 4】',
      content: '【填空：請在此輸入關於這個位置的歷史文化介紹或遊戲提示...】',
    ),
    SpotInfo(
      xPercent: 0.75, yPercent: 0.55, // 最右側建築
      title: '【填空：建築名稱 5】',
      content: '【填空：請在此輸入關於這個位置的歷史文化介紹或遊戲提示...】',
    ),
  ];
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC3B49E), // 仿舊背景底色
      body: Listener(
        // 全域捕捉鼠標位置，讓提示框跟隨或定位
        onPointerHover: (event) {
          if (_hoveredSpot != null) {
            setState(() {
              _mousePosition = event.position;
            });
          }
        },
        child: Stack(
          children: [
            // 1. 背景裝飾 (如果有四角的素材可以放在這層)
            // 2. 中間的主體建築與燈泡
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100.0), // 預留底部選單空間
                child: _buildTempleWithPins(),
              ),
            ),

            // 3. 底部選單導覽列
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomMenu(),
            ),

            // 4. 懸浮提示框 (疊在最上層)
            if (_hoveredSpot != null)
              Positioned(
                // 讓提示框出現在鼠標的右上方
                left: _mousePosition.dx + 15,
                top: _mousePosition.dy - 100,
                child: _buildTooltipBox(_hoveredSpot!),
              ),
          ],
        ),
      ),
    );
  }

  // 建立中間的廟宇圖片與其上的燈泡
  Widget _buildTempleWithPins() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 設定圖片的最大寬度，避免在大螢幕上過大
        double imageWidth = constraints.maxWidth > 600 ? 600 : constraints.maxWidth * 0.9;
        // 假設原圖的長寬比例約為 4:3，可依據你的真實圖片調整
        double imageHeight = imageWidth * 0.75;

        return SizedBox(
          width: imageWidth,
          height: imageHeight,
          child: Stack(
            children: [
              // 廟宇底圖
              Positioned.fill(
                child: Image.asset(
                  'assets/temple_center.png', // 請替換成你裁切好的廟宇去背圖
                  fit: BoxFit.contain,
                ),
              ),
              // 疊加燈泡
              ...spots.map((spot) => Positioned(
                left: imageWidth * spot.xPercent - 15, // -15 為了讓圖示中心點對準座標
                top: imageHeight * spot.yPercent - 15,
                child: _buildLightbulbPin(spot),
              )),
            ],
          ),
        );
      },
    );
  }

  // 獨立的燈泡元件
  Widget _buildLightbulbPin(SpotInfo spot) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hoveredSpot = spot);
      },
      onExit: (_) {
        setState(() => _hoveredSpot = null);
      },
      child: const Icon(
        Icons.lightbulb_outline, // 使用內建的燈泡線條圖示
        size: 30,
        color: Colors.black,
        shadows: [
          Shadow(color: Colors.white70, blurRadius: 10), // 加上發光陰影讓其更明顯
        ],
      ),
    );
  }

  // 獨立的提示框元件
  Widget _buildTooltipBox(SpotInfo spot) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE8D0A5), // 淺卡其/黃底色
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              offset: Offset(2, 4),
              blurRadius: 6,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              spot.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              spot.content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 底部導覽列選單
  Widget _buildBottomMenu() {
    return Container(
      padding: const EdgeInsets.only(bottom: 40, top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildMenuButton(Icons.construction, '建構\n古堡'),
          const SizedBox(width: 20),
          _buildMenuButton(Icons.colorize, '發動\n攻擊'), // Flutter內建較少劍的圖示，先用滴管代用，建議後續換自定義 asset
          const SizedBox(width: 20),
          _buildMenuButton(Icons.groups, '小組\n資訊'),
          const SizedBox(width: 20),
          _buildMenuButton(Icons.account_balance, '古蹟\n介紹'), // 拱門形狀
          const SizedBox(width: 20),
          _buildMenuButton(Icons.fort, '編輯\n古堡'), // 城堡圖示
        ],
      ),
    );
  }

  // 單一底部按鈕元件
  Widget _buildMenuButton(IconData icon, String label) {
    return InkWell(
      onTap: () {
        // TODO: 點擊導覽列的邏輯
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.black87),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}