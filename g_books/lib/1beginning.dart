import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 避免鍵盤彈出時出現 Overflow，使用 SingleChildScrollView 搭配 MediaQuery
      body: Stack(
        children: [
          // 1. 背景圖片 (請將您的背景圖放置於 assets 資料夾並在 pubspec.yaml 中宣告)
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/background_image.png'), // 替換成你的背景圖路徑
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. 前景 UI 內容
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 標題 G-BOOKS
                    const Text(
                      'G-BOOKS',
                      style: TextStyle(
                        fontFamily: 'PixelFont', // 請記得在 pubspec.yaml 加入你的像素字體
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4.0,
                        shadows: [
                          Shadow(
                            offset: Offset(2, 2),
                            blurRadius: 4,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 60), // 標題與輸入框的間距

                    // 小組代碼輸入框
                    _buildInputField('小組代碼'),

                    const SizedBox(height: 20),

                    // 座號輸入框
                    _buildInputField('座號'),

                    const SizedBox(height: 40),

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

  // 獨立出的輸入框元件
  Widget _buildInputField(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(
                color: Colors.black, // 粗黑邊框
                width: 2.0,
              ),
            ),
            child: const TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 獨立出的按鈕元件
  Widget _buildLoginButton() {
    return Container(
      width: 160,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF7D4E4B), // 提取原圖中的紅褐色
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: Colors.black,
          width: 2.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            offset: Offset(0, 4),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            // 處理登入邏輯
          },
          child: const Center(
            child: Text(
              '登入',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                letterSpacing: 4.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}