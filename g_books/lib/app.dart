import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'state/app_state.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/upload_avatar_screen.dart';
import 'features/auth/group_naming_screen.dart';
import 'features/heritage/heritage_selection_screen.dart';
import 'features/heritage/my_heritage_screen.dart';
import 'features/heritage/slot_editor_screen.dart';

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
        GoRoute(
          path: '/setup/personal-avatar',
          pageBuilder: (_, state) =>
              _fadePage(state, const UploadAvatarScreen(isGroup: false)),
        ),
        GoRoute(
          path: '/setup/group-avatar',
          pageBuilder: (_, state) =>
              _fadePage(state, const UploadAvatarScreen(isGroup: true)),
        ),
        GoRoute(
          path: '/setup/group-name',
          pageBuilder: (_, state) =>
              _fadePage(state, const GroupNamingScreen()),
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
        GoRoute(
          path: '/slot-editor/:hid',
          pageBuilder: (_, state) => _fadePage(
            state,
            SlotEditorScreen(heritageId: state.pathParameters['hid']!),
          ),
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
    final loggedIn = widget.appState.isLoggedIn;
    final setupDone = widget.appState.isSetupComplete;
    final path = state.matchedLocation;

    if (!loggedIn) {
      return path == '/login' ? null : '/login';
    }
    // 已登入卻還停在登入頁（含登出後重新登入）：依是否完成設定導向對應起點。
    if (path == '/login') {
      return setupDone ? '/heritage-selection' : '/setup/personal-avatar';
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
