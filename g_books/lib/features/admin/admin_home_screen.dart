import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/avatar_image.dart';
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import '../../services/account_service.dart';
import '../../state/app_state.dart';

/// 管理者後台首頁（側欄分頁）：
/// - 古蹟設定：選擇要編輯的古蹟 → 進入編輯器（slot / 原料對應 / 物品）。
/// - 教師帳號：管理老師登入帳號（role=1）。小組帳號由教師控制台管理，不在此處。
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const _bg = Color(0xFF15171A);
  static const _panel = Color(0xFF1E2125);
  static const _gold = Color(0xFFD4A843);

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            _nav(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: _tab == 0
                    ? const _HeritagePickerBody()
                    : const _TeacherAccountsBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav() {
    final staff = context.watch<AppState>().currentStaff;
    const items = [
      (Icons.account_balance_rounded, '古蹟設定'),
      (Icons.manage_accounts_rounded, '教師帳號'),
    ];
    return Container(
      width: 210,
      color: _panel,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded,
                    color: _gold, size: 24),
                SizedBox(width: 8),
                Text('管理者後台',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Text(staff?.displayName ?? '',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          for (var i = 0; i < items.length; i++)
            _navItem(items[i].$1, items[i].$2, i),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: Colors.white70),
            label: const Text('登出',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final on = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: on ? _gold.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? _gold.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: on ? _gold : Colors.white60),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: on ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── 古蹟設定分頁 ──────────────────────────────────────────────────────────────
class _HeritagePickerBody extends StatelessWidget {
  const _HeritagePickerBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header('選擇要編輯的古蹟', '進入編輯器設定 slot 幾何 / 原料對應 / 物品'),
        const SizedBox(height: 18),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              childAspectRatio: 0.74,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
            ),
            itemCount: mockHeritages.length,
            itemBuilder: (_, i) => _HeritageTile(
              heritage: mockHeritages[i],
              onTap: () => context.push('/admin/edit/${mockHeritages[i].id}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeritageTile extends StatelessWidget {
  final HeritageModel heritage;
  final VoidCallback onTap;
  const _HeritageTile({required this.heritage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (heritage.cardImagePath.isNotEmpty)
              Image.asset(heritage.cardImagePath, fit: BoxFit.cover)
            else
              const ColoredBox(color: Color(0xFF24272A)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heritage.name.isNotEmpty ? heritage.name : '（未命名）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 14, color: Color(0xFFD4A843)),
                      SizedBox(width: 4),
                      Text('編輯設定',
                          style: TextStyle(
                              color: Color(0xFFD4A843), fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 教師帳號分頁 ──────────────────────────────────────────────────────────────
class _TeacherAccountsBody extends StatefulWidget {
  const _TeacherAccountsBody();

  @override
  State<_TeacherAccountsBody> createState() => _TeacherAccountsBodyState();
}

class _TeacherAccountsBodyState extends State<_TeacherAccountsBody> {
  static const _panel = Color(0xFF1E2125);
  static const _field = Color(0xFF14161A);
  static const _gold = Color(0xFFD4A843);

  late final AccountService _svc;

  List<TeacherAccount> _teachers = const [];
  bool _loading = false;

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc = context.read<AccountService>();
    _refresh();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.listTeachers();
      if (mounted) setState(() => _teachers = list);
    } catch (e) {
      _toast('讀取失敗：${_msg(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTeacher() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      _toast('請輸入帳號與密碼');
      return;
    }
    try {
      await _svc.createTeacher(username: user, password: pass);
      _userCtrl.clear();
      _passCtrl.clear();
      await _refresh();
      _toast('已建立老師帳號「$user」');
    } catch (e) {
      _toast('建立失敗：${_msg(e)}');
    }
  }

  Future<void> _deleteTeacher(TeacherAccount t) async {
    final ok = await _confirm('刪除老師帳號', '確定刪除「${t.username}」？此操作無法復原。', '刪除');
    if (ok != true) return;
    try {
      await _svc.deleteTeacher(username: t.username);
      await _refresh();
      _toast('已刪除「${t.username}」');
    } catch (e) {
      _toast('刪除失敗：${_msg(e)}');
    }
  }

  Future<void> _resetPassword(TeacherAccount t) async {
    final pwd = await _askPassword(t.username);
    if (pwd == null) return; // 取消
    try {
      await _svc.resetTeacherPassword(username: t.username, newPassword: pwd);
      _toast('已重設「${t.username}」的密碼');
    } catch (e) {
      _toast('重設失敗：${_msg(e)}（此功能需後端開放管理者重設密碼）');
    }
  }

  /// 輸入新密碼對話框。回傳新密碼，或 null（取消 / 空白）。
  Future<String?> _askPassword(String username) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('重設「$username」密碼',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          onSubmitted: (v) =>
              Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          decoration: InputDecoration(
            hintText: '輸入新密碼',
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
            filled: true,
            fillColor: _field,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF2A1A0A)),
            child: const Text('重設',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String body, String confirmText) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF2A1A0A)),
            child: Text(confirmText,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _msg(Object e) => e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('ApiException', '錯誤');

  void _toast(String m) =>
      Fluttertoast.showToast(msg: m, gravity: ToastGravity.BOTTOM);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header('教師帳號', '建立 / 刪除 / 重設老師登入帳號（小組帳號由教師控制台管理）',
            trailing: IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
              tooltip: '重新整理',
            )),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              _card(
                '建立老師帳號',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('帳號＝老師登入用；密碼自訂',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 3, child: _input(_userCtrl, '帳號')),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: _input(_passCtrl, '密碼')),
                        const SizedBox(width: 12),
                        _primaryBtn('建立', _addTeacher),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card('老師帳號（${_teachers.length}）', _listView()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _listView() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    if (_teachers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('尚無老師帳號', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: [
        for (final t in _teachers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                _avatar(t.avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.username,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                ),
                TextButton.icon(
                  onPressed: () => _resetPassword(t),
                  icon: const Icon(Icons.key_rounded,
                      size: 16, color: Colors.white54),
                  label: const Text('重設密碼',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                IconButton(
                  onPressed: () => _deleteTeacher(t),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white38, size: 20),
                  tooltip: '刪除帳號',
                  splashRadius: 20,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _avatar(String? rawUrl, {double size = 34}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _field,
        border: Border.all(color: Colors.white24),
      ),
      child: ClipOval(
        child: AvatarImage(
          url: rawUrl,
          width: size,
          height: size,
          placeholder: Icon(Icons.school_rounded,
              size: size * 0.62, color: Colors.white38),
        ),
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _gold, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
        filled: true,
        fillColor: _field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _primaryBtn(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        foregroundColor: const Color(0xFF2A1A0A),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

// ── 共用標題 ──────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _Header(this.title, this.subtitle, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
