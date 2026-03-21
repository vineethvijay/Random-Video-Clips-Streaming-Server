import 'package:flutter/material.dart';

import '../services/streaming_api.dart';
import 'admin_screen.dart';
import 'home_screen.dart';
import 'stats_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api});

  final StreamingApi api;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(api: widget.api),
      AdminScreen(api: widget.api),
      StatsScreen(api: widget.api),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
          NavigationDestination(icon: Icon(Icons.query_stats), label: 'Stats'),
        ],
      ),
    );
  }
}
