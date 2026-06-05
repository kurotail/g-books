import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 類似羊皮紙/沙地的底色
      backgroundColor: const Color(0xFFD4C4AC),
      body: Stack(
        children: [
          // 1. 背景寺廟圖片 (請將去背的寺廟圖片放入 assets)
          Center(
            child: Opacity(
              opacity: 0.3, // 調整透明度讓背景不搶戲
              child: Image.asset(
                'assets/temple_bg.png', // 替換為你的圖片路徑
                fit: BoxFit.contain,
              ),
            ),
          ),

          // 2. 前景 UI (使用 SafeArea 與 ScrollView 避免鍵盤遮擋)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // G-BOOKS 標題
                    const Text(
                      'G-BOOKS',
                      style: TextStyle(
                        fontFamily: 'PixelFont', // 需在 pubspec.yaml 設定像素字體
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4.0,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 4),
                            blurRadius: 0,
                            color: Colors.black26,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 60),

                    // 小組代碼輸入區
                    _buildInputField('小組代碼'),
                    const SizedBox(height: 24),

                    // 座號輸入區
                    _buildInputField('座號'),
                    const SizedBox(height: 50),

                    // 登入按鈕
                    _buildLoginButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 封裝的輸入框元件
  Widget _buildInputField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: Colors.black, // 粗黑邊框
              width: 2.0,
            ),
          ),
          child: const TextField(
            decoration: InputDecoration(
              border: InputBorder.none, // 隱藏原本的底線
              contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
          ),
        ),
      ],
    );
  }

  // 封裝的登入按鈕元件
  Widget _buildLoginButton() {
    return Container(
      width: 160,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF7B4A45), // 抓取原圖的紅褐色
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            // TODO: 在這裡加入登入邏輯
          },
          child: const Center(
            child: Text(
              '登入',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                letterSpacing: 4.0, // 讓字距拉開一點
              ),
            ),
          ),
        ),
      ),
    );
  }
}