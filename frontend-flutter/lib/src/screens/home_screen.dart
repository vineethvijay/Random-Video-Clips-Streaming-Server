import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';

import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../providers/video_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_progress_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loader.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _progressTimer = Timer.periodic(
        const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  String _fmtSec(num? sec) {
    if (sec == null || sec < 0) return '0:00';
    final m = sec ~/ 60;
    final s = sec.toInt() % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _refresh() async {
    ref.read(streamStatusProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(streamStatusProvider);
    final config = ref.read(apiProvider).config;
    final width = MediaQuery.sizeOf(context).width;
    final useWideLayout = width >= AppTheme.breakpointTablet;

    // ── Now-playing sidebar ──
    Widget nowPlaying = streamAsync.when(
      data: (st) => _buildNowPlayingSection(context, st),
      loading: () => const ShimmerLoader(height: 100),
      error: (_, __) => const SizedBox.shrink(),
    );

    if (useWideLayout) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                SectionHeader(
                  title: 'Dashboard',
                  subtitle: 'Live streaming control',
                  icon: Icons.dashboard_rounded,
                  onRefresh: _refresh,
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 70,
                        child: _buildPlayerCard(context, config.enableLiveStream),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 30,
                        child: SingleChildScrollView(child: nowPlaying),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Mobile: stacked vertical ──
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              SectionHeader(
                title: 'Dashboard',
                subtitle: 'Live streaming control',
                icon: Icons.dashboard_rounded,
                onRefresh: _refresh,
              ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
              const SizedBox(height: 12),
              _buildPlayerCard(context, config.enableLiveStream),
              const SizedBox(height: 12),
              nowPlaying,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(BuildContext context, bool enabled) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!enabled) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.live_tv_rounded, size: 18, color: AppTheme.accentEmerald),
              const SizedBox(width: 8),
              Text('Live Stream', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text('Rebuild with ENABLE_LIVE_STREAM=true to enable the embedded HLS player.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    final vpState = ref.watch(videoPlayerProvider);
    final vpNotifier = ref.read(videoPlayerProvider.notifier);
    final api = ref.read(apiProvider);
    final controller = vpState.controller;
    final initialized = vpState.isInitialized;
    final videoError = vpState.videoError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Video surface ──
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (videoError != null) ...[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(videoError,
                        style: tt.bodySmall?.copyWith(color: cs.onErrorContainer)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(spacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: () => vpNotifier.retry(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                    if (initialized)
                      FilledButton.icon(
                        onPressed: () => vpNotifier.play(),
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: const Text('Play'),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              if (initialized && controller != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: Stack(
                      children: [
                        VideoPlayer(controller),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => vpNotifier.togglePlayPause(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (videoError == null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
            ],
          ),
        ),
        // ── YouTube-style controls bar ──
        if (initialized && controller != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Row(
              children: [
                // Play / Pause
                IconButton(
                  onPressed: () => vpNotifier.togglePlayPause(),
                  icon: Icon(controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  iconSize: 28,
                  tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
                ),
                const SizedBox(width: 4),
                // Skip Video
                IconButton(
                  onPressed: () async {
                    await api.skipToNext();
                    _toast('Skipping video…');
                  },
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: 24,
                  tooltip: 'Skip Video',
                ),
                const SizedBox(width: 4),
                // Skip Audio
                IconButton(
                  onPressed: () async {
                    await api.skipToNextAudio();
                    _toast('Skipping audio…');
                  },
                  icon: const Icon(Icons.music_off_rounded),
                  iconSize: 22,
                  tooltip: 'Skip Audio',
                ),
                const SizedBox(width: 8),
                // Volume
                IconButton(
                  onPressed: () async {
                    final vol = controller.value.volume;
                    await vpNotifier.setVolume(vol > 0 ? 0 : 1.0);
                  },
                  icon: Icon(controller.value.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded),
                  iconSize: 20,
                  tooltip: 'Mute',
                ),
                SizedBox(
                  width: 90,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.surfaceContainerHighest,
                      thumbColor: cs.primary,
                    ),
                    child: Slider(
                      value: controller.value.volume,
                      onChanged: (v) => vpNotifier.setVolume(v),
                    ),
                  ),
                ),
                const Spacer(),
                // LIVE badge
                if (controller.value.isPlaying)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentEmerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accentEmerald,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('LIVE',
                            style: tt.labelSmall?.copyWith(
                                color: AppTheme.accentEmerald, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Widget _buildNowPlayingSection(BuildContext context, dynamic st) {
    final tt = Theme.of(context).textTheme;

    final chunkProgress = _chunkProgress(st);
    final audioProgress = _audioProgress(st);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Now Playing',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          // Current chunk
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.nowPlayingBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.live_tv_rounded,
                    size: 20, color: AppTheme.nowPlayingBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st.currentChunk ?? 'No video',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    AnimatedProgressBar(
                      progress: chunkProgress,
                      elapsedLabel: _fmtSec(_chunkElapsed(st)),
                      totalLabel: _fmtSec(st.currentChunkDuration),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Current audio
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentEmerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_note_rounded,
                    size: 20, color: AppTheme.accentEmerald),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st.currentAudio ?? 'No audio',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    AnimatedProgressBar(
                      progress: audioProgress,
                      elapsedLabel: _fmtSec(st.audioPositionSec),
                      totalLabel: _fmtSec(st.audioTrackDurationSec),
                      startColor: AppTheme.accentEmerald.withValues(alpha: 0.6),
                      endColor: AppTheme.accentEmerald,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
  }

  double _chunkProgress(dynamic st) {
    final startedAt = st.currentChunkStartedAt;
    final duration = st.currentChunkDuration;
    if (startedAt == null || duration == null || duration <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return ((now - startedAt.toDouble()) / duration.toDouble()).clamp(0.0, 1.0);
  }

  num? _chunkElapsed(dynamic st) {
    final startedAt = st.currentChunkStartedAt;
    final duration = st.currentChunkDuration;
    if (startedAt == null || duration == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return (now - startedAt.toDouble()).clamp(0.0, duration.toDouble());
  }

  double _audioProgress(dynamic st) {
    final pos = st.audioPositionSec;
    final dur = st.audioTrackDurationSec;
    if (pos != null && dur != null && dur > 0) {
      return (pos / dur).clamp(0.0, 1.0);
    }
    return 0;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
