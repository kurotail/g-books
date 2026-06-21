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
  bool _saving = false;
  String? _error;

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

  Future<void> _confirm() async {
    if (_saving) return;
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '請輸入小組名稱');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // 命名 = 改顯示名稱 display_name（不影響登入帳號 / token，免重新登入）。
    final err = await context.read<AppState>().setGroupName(name);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
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
            top: 32,
            right: 56,
            child: GestureDetector(
              onTap: () => context.go('/setup/group-avatar'),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.pillDark,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
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
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
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
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.buttonDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
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
