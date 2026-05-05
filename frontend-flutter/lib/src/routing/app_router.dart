import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/admin_screen.dart';
import '../screens/app_shell.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/stats_screen.dart';

final appRouter = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const HomeScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/library',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const LibraryScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/stats',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const StatsScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const AdminScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
      ],
    ),
  ],
);

Widget _fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child) {
  return FadeTransition(opacity: animation, child: child);
}
