import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'src/screens/admin_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/stats_screen.dart';
import 'src/services/streaming_api.dart';
import 'src/theme/app_theme.dart';

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
      title: 'Random Video Streamer',
      theme: AppTheme.dark(),
    );
  }
}
