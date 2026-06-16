import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../state/app_state.dart';

/// 教師 / 管理者登入：帳號 + 密碼。登入成功後由 go_router redirect 依角色導向
/// 管理者後台（/admin）或教師頁（/teacher）。
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  String? _error;
  bool _loggingIn = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loggingIn) return;
    final user = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (user.isEmpty || pwd.isEmpty) {
      setState(() => _error = '請輸入帳號與密碼');
      return;
    }
    final appState = context.read<AppState>();
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    final err = await appState.loginAsStaff(user, pwd);
    if (!mounted) return;
    setState(() {
      _loggingIn = false;
      if (err != null) _error = err;
    });
    // 成功時 refreshListenable 觸發 redirect 自動導向。
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentScaffold(
      child: Stack(
        children: [
          // 左下角：返回學生登入（與學生登入頁的「教師/管理者登入」同位置、同樣式）
          Positioned(
            left: 20,
            bottom: 16,
            child: GestureDetector(
              onTap: () => context.go('/login'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.pillDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('返回學生登入',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        )),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _banner(),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('帳號'),
                        const SizedBox(height: 8),
                        _field(_userCtrl, '請輸入帳號'),
                        const SizedBox(height: 20),
                        _label('密碼'),
                        const SizedBox(height: 8),
                        _field(_pwdCtrl, '請輸入密碼', obscure: true),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 32),
                        _loginButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0x14000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33000000)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined,
                size: 20, color: AppColors.labelText),
            SizedBox(width: 10),
            Text(
              '教師 / 管理者登入',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.labelText,
              ),
            ),
          ],
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.labelText,
        ),
      );

  Widget _field(TextEditingController ctrl, String hint,
      {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _login(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inputHint, fontSize: 14),
        filled: true,
        fillColor: AppColors.inputFieldBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
    );
  }

  Widget _loginButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loggingIn ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 0,
          ),
          child: _loggingIn
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text(
                  '登 入',
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      );
}
