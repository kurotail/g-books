import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _seatCtrl = TextEditingController();
  String? _error;
  bool _loggingIn = false;
  DateTime? _lastBackPress;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _seatCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loggingIn) return;
    final name = _nameCtrl.text.trim();
    final seat = _seatCtrl.text.trim();
    if (name.isEmpty || seat.isEmpty) {
      setState(() => _error = '請輸入姓名與座號');
      return;
    }
    final appState = context.read<AppState>();
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    final err = await appState.login(name, seat);
    if (!mounted) return;
    setState(() {
      _loggingIn = false;
      if (err != null) _error = err;
    });
    // 成功時由 GoRouter refreshListenable 觸發導向。
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
        } else {
          _lastBackPress = now;
          Fluttertoast.showToast(
            msg: '再按一次返回鍵以退出',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
          );
        }
      },
      child: ParchmentScaffold(
        backgroundImage: 'assets/images/bg_login.png',
        child: Stack(
          children: [
            // 左下角：教師 / 管理者登入入口
            Positioned(
              left: 20,
              bottom: 16,
              child: GestureDetector(
                onTap: () => context.push('/staff-login'),
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
                      Icon(Icons.admin_panel_settings_outlined,
                          size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        '教師 / 管理者登入',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Login form
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _infoBanner(),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('姓名'),
                          const SizedBox(height: 8),
                          _textField(_nameCtrl, '請輸入姓名'),
                          const SizedBox(height: 20),
                          _label('座號'),
                          const SizedBox(height: 8),
                          _textField(_seatCtrl, '請輸入座號', isNumber: true),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
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
      ),
    );
  }

  Widget _infoBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0x14000000),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x33000000)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline_rounded, size: 20, color: AppColors.labelText),
        SizedBox(width: 10),
        Text(
          '請輸入姓名與座號登入',
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

  Widget _textField(
    TextEditingController ctrl,
    String hint, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inputHint, fontSize: 14),
        filled: true,
        fillColor: AppColors.inputFieldBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      child: _loggingIn
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
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
