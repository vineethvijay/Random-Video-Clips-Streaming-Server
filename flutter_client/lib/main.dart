import 'package:flutter/material.dart';

import 'src/screens/app_shell.dart';
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
    return MaterialApp(
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
      home: AppShell(api: api),
    );
  }
}
