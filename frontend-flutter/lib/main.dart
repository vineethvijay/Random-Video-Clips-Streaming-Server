import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/routing/app_router.dart';
import 'src/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: RandomVideoStreamerApp()));
}

class RandomVideoStreamerApp extends StatelessWidget {
  const RandomVideoStreamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      title: 'Random Video Streamer',
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          SelectionArea(child: child ?? const SizedBox.shrink()),
    );
  }
}
