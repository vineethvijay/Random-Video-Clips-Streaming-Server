import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'src/screens/admin_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/stats_screen.dart';
import 'src/services/streaming_api.dart';

void main() {
  final api = StreamingApi.fromEnvironment();
  runApp(RandomVideoStreamerApp(api: api));
}

class RandomVideoStreamerApp extends StatelessWidget {
  const RandomVideoStreamerApp({super.key, required this.api});

  final StreamingApi api;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => HomeScreen(api: api)),
        GoRoute(path: '/admin', builder: (context, state) => AdminScreen(api: api)),
        GoRoute(path: '/stats', builder: (context, state) => StatsScreen(api: api)),
      ],
    );

    return MaterialApp.router(
      routerConfig: router,
      builder: (context, child) {
        return SelectionArea(
          child: child ?? const SizedBox.shrink(),
        );
      },
      title: 'Random Video Streamer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        cardTheme: CardThemeData(
          color: const Color(0xFF111C36),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF273B66)),
          ),
        ),
        useMaterial3: true,
      ),
    );
  }
}
