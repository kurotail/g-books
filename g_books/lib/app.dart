import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/models/staff_account.dart';
import 'state/app_state.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/upload_avatar_screen.dart';
import 'features/auth/group_naming_screen.dart';
import 'features/auth/group_overview_screen.dart';
import 'features/heritage/heritage_selection_screen.dart';
import 'features/heritage/my_heritage_screen.dart';
import 'features/admin/staff_login_screen.dart';
import 'features/admin/admin_heritage_picker_screen.dart';
import 'features/admin/admin_editor_screen.dart';
import 'features/admin/teacher_home_screen.dart';

class GBooksApp extends StatefulWidget {
  final AppState appState;

  const GBooksApp({super.key, required this.appState});

  @override
  State<GBooksApp> createState() => _GBooksAppState();
}

class _GBooksAppState extends State<GBooksApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      refreshListenable: widget.appState,
      initialLocation: '/login',
      redirect: _redirect,
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (_, state) => _fadePage(state, const LoginScreen()),
        ),
        // 教師 / 管理者登入與後台。
        GoRoute(
          path: '/staff-login',
          pageBuilder: (_, state) => _fadePage(state, const StaffLoginScreen()),
        ),
        GoRoute(
          path: '/teacher',
          pageBuilder: (_, state) => _fadePage(state, const TeacherHomeScreen()),
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (_, state) =>
              _fadePage(state, const AdminHeritagePickerScreen()),
        ),
        GoRoute(
          path: '/admin/edit/:hid',
          pageBuilder: (_, state) => _fadePage(
            state,
            AdminEditorScreen(heritageId: state.pathParameters['hid']!),
          ),
        ),
        GoRoute(
          path: '/setup/group-avatar',
          pageBuilder: (_, state) => _fadePage(
            state,
            const UploadAvatarScreen(target: AvatarTarget.group),
          ),
        ),
        GoRoute(
          path: '/setup/group-name',
          pageBuilder: (_, state) =>
              _fadePage(state, const GroupNamingScreen()),
        ),
        // 小組總攬「不」放在 /setup 下：除了初次設定，檢視古蹟時也能從面板進來
        // 補設組員頭像，不該被「已完成設定就擋掉 /setup」的導向攔截。
        // （組員頭像上傳改由總攬以根 Navigator 推出，不再是 go_router 路由。）
        GoRoute(
          path: '/group-overview',
          pageBuilder: (_, state) =>
              _fadePage(state, const GroupOverviewScreen()),
        ),
        GoRoute(
          path: '/heritage-selection',
          pageBuilder: (_, state) =>
              _fadePage(state, const HeritageSelectionScreen()),
        ),
        GoRoute(
          path: '/my-heritage',
          pageBuilder: (_, state) =>
              _fadePage(state, const MyHeritageScreen()),
        ),
      ],
    );
  }

  static CustomTransitionPage<void> _fadePage(
    GoRouterState state,
    Widget child,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final s = widget.appState;
    final loggedIn = s.isLoggedIn;
    final staff = s.isStaffLoggedIn;
    final setupDone = s.isSetupComplete;
    final path = state.matchedLocation;

    // 教師 / 管理者已登入：鎖在各自的後台區。
    if (staff) {
      if (s.staffRole == StaffRole.admin) {
        return path.startsWith('/admin') ? null : '/admin';
      }
      return path == '/teacher' ? null : '/teacher';
    }
    // 皆未登入：允許學生登入頁與教師 / 管理者登入頁。
    if (!loggedIn) {
      return (path == '/login' || path == '/staff-login') ? null : '/login';
    }
    // 學生已登入卻還停在任一登入頁：依是否完成設定導向對應起點。
    // 初次登入由小組頭像開始（個人頭像改於小組總攬設定）。
    if (path == '/login' || path == '/staff-login') {
      return setupDone ? '/heritage-selection' : '/setup/group-avatar';
    }
    // 已完成設定卻想回到設定流程：擋下，導到古蹟選擇。
    if (setupDone && path.startsWith('/setup')) {
      return '/heritage-selection';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'G-Books 蹟不可師',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6914)),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}
