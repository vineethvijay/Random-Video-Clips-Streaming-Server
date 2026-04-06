import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player_bar.dart';

/// Adaptive navigation shell: bottom bar on mobile, rail on wider screens.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static int _index(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/library')) return 1;
    if (path.startsWith('/stats')) return 2;
    if (path.startsWith('/admin')) return 3;
    return 0;
  }

  static const _tabs = <_Tab>[
    _Tab('Home', '/', Icons.dashboard_rounded),
    _Tab('Library', '/library', Icons.video_library_rounded),
    _Tab('Stats', '/stats', Icons.bar_chart_rounded),
    _Tab('Admin', '/admin', Icons.admin_panel_settings_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final idx = _index(context);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= AppTheme.breakpointTablet;

    // Mini player data
    final streamAsync = ref.watch(streamStatusProvider);
    final st = streamAsync.valueOrNull;
    final chunk = st?.currentChunk;
    final audio = st?.currentAudio;
    final api = ref.read(apiProvider);

    double chunkProgress = 0;
    if (st != null) {
      final started = st.currentChunkStartedAt;
      final dur = st.currentChunkDuration;
      if (started != null && dur != null && dur > 0) {
        final now = DateTime.now().millisecondsSinceEpoch / 1000;
        chunkProgress = ((now - started.toDouble()) / dur.toDouble()).clamp(0.0, 1.0);
      }
    }

    void navigate(int i) {
      if (i != idx) context.go(_tabs[i].path);
    }

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: idx,
              onDestinationSelected: navigate,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Icon(Icons.stream_rounded, color: cs.primary, size: 28),
              ),
              destinations: _tabs.map((t) {
                return NavigationRailDestination(
                  icon: Icon(t.icon),
                  selectedIcon: _GlowIcon(icon: t.icon, color: cs.primary),
                  label: Text(t.label),
                );
              }).toList(),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outline.withValues(alpha: 0.12),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: child),
                  MiniPlayerBar(
                    currentChunk: chunk,
                    currentAudio: audio,
                    chunkProgress: chunkProgress,
                    onSkipVideo: () => api.skipToNext(),
                    onSkipAudio: () => api.skipToNextAudio(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile: bottom nav bar
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          MiniPlayerBar(
            currentChunk: chunk,
            currentAudio: audio,
            chunkProgress: chunkProgress,
            onSkipVideo: () => api.skipToNext(),
            onSkipAudio: () => api.skipToNextAudio(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: navigate,
          destinations: _tabs.map((t) {
            return NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: _GlowIcon(icon: t.icon, color: cs.primary),
              label: t.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

/// Wraps the active icon with a subtle glow background.
class _GlowIcon extends StatelessWidget {
  const _GlowIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.15),
      ),
      child: Icon(icon, color: color),
    );
  }
}
