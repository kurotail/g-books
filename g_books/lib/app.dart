import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'state/app_state.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/upload_avatar_screen.dart';
import 'features/auth/group_naming_screen.dart';
import 'features/heritage/heritage_selection_screen.dart';

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
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/setup/personal-avatar',
          builder: (_, _) => const UploadAvatarScreen(isGroup: false),
        ),
        GoRoute(
          path: '/setup/group-avatar',
          builder: (_, _) => const UploadAvatarScreen(isGroup: true),
        ),
        GoRoute(
          path: '/setup/group-name',
          builder: (_, _) => const GroupNamingScreen(),
        ),
        GoRoute(
          path: '/heritage-selection',
          builder: (_, _) => const HeritageSelectionScreen(),
        ),
      ],
    );
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final loggedIn = widget.appState.isLoggedIn;
    final setupDone = widget.appState.isSetupComplete;
    final path = state.matchedLocation;

    if (!loggedIn) {
      return path == '/login' ? null : '/login';
    }
    if (setupDone && path.startsWith('/setup')) {
      return '/heritage-selection';
    }
    if (!setupDone && path == '/login') {
      return '/setup/personal-avatar';
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
