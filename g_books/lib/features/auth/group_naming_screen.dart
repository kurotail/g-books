import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../core/widgets/step_indicator.dart';
import '../../core/widgets/avatar_frame.dart';
import '../../state/app_state.dart';

class GroupNamingScreen extends StatefulWidget {
  const GroupNamingScreen({super.key});

  @override
  State<GroupNamingScreen> createState() => _GroupNamingScreenState();
}

class _GroupNamingScreenState extends State<GroupNamingScreen> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 回到此頁時帶回先前輸入的組名（返回上一步不遺失已設定資料）。
    _ctrl.text = context.read<AppState>().currentGroup?.name ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    context.read<AppState>().setGroupName(name);
    context.go('/group-overview');
  }

  @override
  Widget build(BuildContext context) {
    final group = context.watch<AppState>().currentGroup;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/setup/group-avatar');
      },
      child: ParchmentScaffold(
      child: Stack(
        children: [
          // Back arrow（往畫面內側收一點，避免太靠近螢幕邊緣）
          Positioned(
            top: 36,
            right: 64,
            child: GestureDetector(
              onTap: () => context.go('/setup/group-avatar'),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 24,
                color: Color(0xFF6A6A6A),
              ),
            ),
          ),
          // Step indicator
          const Positioned(
            right: 40,
            top: 0,
            bottom: 0,
            width: 160,
            child: Center(
              child: StepIndicator(
                steps: ['登陸帳號', '小組頭像', '小組命名', '小組建立成功'],
                currentStep: 2,
              ),
            ),
          ),
          // Main content
          Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顯示前一頁設定好的小組頭像
                    AvatarFrame(size: 130, imageUrl: group?.avatarUrl),
                    const SizedBox(height: 24),
                    const Text(
                      '為你的小組命名吧！',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labelText,
                      ),
                    ),
                    const SizedBox(height: 36),
                    TextField(
                      controller: _ctrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: '請輸入小組名稱',
                        hintStyle: const TextStyle(color: AppColors.inputHint, fontSize: 15),
                        filled: true,
                        fillColor: AppColors.inputFieldBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.buttonDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '確 定',
                          style: TextStyle(
                            fontSize: 20,
                            letterSpacing: 6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
