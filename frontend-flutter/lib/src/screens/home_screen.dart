import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';

import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_progress_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/stat_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  VideoPlayerController? _videoController;
  String? _videoError;
  bool _playerCollapsed = true;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    final config = ref.read(apiProvider).config;
    if (config.enableLiveStream) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(config.hlsUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )..addListener(_videoListener);
      _initializeVideo();
    }
    _progressTimer = Timer.periodic(
        const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  void _videoListener() {
    final c = _videoController;
    if (c == null || !mounted) return;
    if (c.value.hasError) {
      setState(() {
        _videoError = c.value.errorDescription?.isNotEmpty == true
            ? c.value.errorDescription
            : 'Playback error';
      });
    }
  }

  Future<void> _initializeVideo() async {
    final c = _videoController;
    if (c == null) return;
    setState(() => _videoError = null);
    try {
      await c.initialize();
      if (!mounted) return;
      await c.setLooping(true);
      try { await c.play(); } catch (e) {
        if (kIsWeb) setState(() => _videoError = 'Autoplay may be blocked ($e)');
      }
      if (mounted) setState(() => _videoError = null);
    } catch (e) {
      if (mounted) setState(() => _videoError = 'Could not load stream.\n$e');
    }
  }

  Future<void> _retryVideo() async {
    final config = ref.read(apiProvider).config;
    _videoController?.removeListener(_videoListener);
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(config.hlsUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..addListener(_videoListener);
    await _initializeVideo();
    if (mounted) setState(() {});
  }

  String _fmtSec(num? sec) {
    if (sec == null || sec < 0) return '0:00';
    final m = sec ~/ 60;
    final s = sec.toInt() % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(num totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _refresh() async {
    ref.read(streamStatusProvider.notifier).refresh();
    ref.read(chunksProvider.notifier).refresh();
    ref.read(audioFilesProvider.notifier).refresh();
    ref.read(serverStatusProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(streamStatusProvider);
    final chunksAsync = ref.watch(chunksProvider);
    final audioAsync = ref.watch(audioFilesProvider);
    final serverAsync = ref.watch(serverStatusProvider);
    final config = ref.read(apiProvider).config;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Header
                SectionHeader(
                  title: 'Dashboard',
                  subtitle: 'Live streaming control',
                  icon: Icons.dashboard_rounded,
                  onRefresh: _refresh,
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
                const SizedBox(height: 20),

                // Overview strip
                streamAsync.when(
                  data: (st) => _buildOverviewStrip(context, st, chunksAsync, audioAsync),
                  loading: () => const ShimmerStatRow(count: 4),
                  error: (e, _) => _errorCard(context, '$e'),
                ),
                const SizedBox(height: 20),

                // Quick actions
                streamAsync.when(
                  data: (st) => _buildQuickActions(context, st, serverAsync),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),

                // Live player
                _buildPlayerCard(context, config.enableLiveStream),
                const SizedBox(height: 20),

                // Now playing details
                streamAsync.when(
                  data: (st) => _buildNowPlayingSection(context, st),
                  loading: () => const ShimmerLoader(height: 100),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewStrip(BuildContext context, dynamic st, AsyncValue chunksAsync, AsyncValue audioAsync) {
    final chunks = chunksAsync.valueOrNull ?? [];
    final audio = audioAsync.valueOrNull ?? [];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatCard(
          label: 'Chunks',
          value: '${chunks.length}',
          icon: Icons.video_library_rounded,
          gradientStart: AppTheme.accentCyan.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentCyan.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Audio Files',
          value: '${audio.length}',
          icon: Icons.library_music_rounded,
          gradientStart: AppTheme.accentEmerald.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentEmerald.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Streamed',
          value: _fmtDuration(st.totalSecondsStreamed),
          icon: Icons.timer_rounded,
          gradientStart: AppTheme.accentAmber.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentAmber.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Pushed',
          value: '${st.chunksPushed}',
          icon: Icons.upload_rounded,
          gradientStart: AppTheme.accentLavender.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentLavender.withValues(alpha: 0.05),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _buildQuickActions(BuildContext context, dynamic st, AsyncValue serverAsync) {
    final api = ref.read(apiProvider);
    final genRunning = serverAsync.valueOrNull?.generationInProgress == true;

    return Row(
      children: [
        Expanded(
          child: _QuickActionPill(
            icon: Icons.skip_next_rounded,
            label: 'Skip Video',
            color: AppTheme.nowPlayingBlue,
            onTap: () async {
              await api.skipToNext();
              _toast('Skipping video…');
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionPill(
            icon: Icons.skip_next_rounded,
            label: 'Skip Audio',
            color: AppTheme.accentEmerald,
            onTap: () async {
              await api.skipToNextAudio();
              _toast('Skipping audio…');
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionPill(
            icon: genRunning ? Icons.hourglass_top_rounded : Icons.auto_awesome_rounded,
            label: genRunning ? 'Generating…' : 'Generate',
            color: genRunning ? AppTheme.accentAmber : AppTheme.accentLavender,
            onTap: genRunning ? null : () async {
              await api.generateChunks();
              _toast('Chunk generation triggered');
              ref.read(serverStatusProvider.notifier).refresh();
            },
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
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

    final controller = _videoController;
    final initialized = controller?.value.isInitialized ?? false;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Collapsible header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() {
              _playerCollapsed = !_playerCollapsed;
              if (!_playerCollapsed && !initialized) _retryVideo();
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _playerCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text('Live Stream',
                      style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700, color: AppTheme.accentEmerald)),
                  const Spacer(),
                  if (initialized && controller!.value.isPlaying)
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
                            width: 6,
                            height: 6,
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
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
                if (_videoError != null) ...[
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_videoError!,
                          style: tt.bodySmall?.copyWith(color: cs.onErrorContainer)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(spacing: 8, children: [
                      FilledButton.tonalIcon(
                        onPressed: _retryVideo,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                      ),
                      if (initialized && kIsWeb)
                        FilledButton.icon(
                          onPressed: () async {
                            await controller?.play();
                            setState(() {});
                          },
                          icon: const Icon(Icons.play_circle_outline, size: 16),
                          label: const Text('Play'),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                if (initialized && controller != null)
                  GestureDetector(
                    onTap: () async {
                      if (controller.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                      setState(() {});
                    },
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: VideoPlayer(controller),
                      ),
                    ),
                  )
                else if (_videoError == null)
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (initialized && controller != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            if (controller.value.isPlaying) {
                              await controller.pause();
                            } else {
                              await controller.play();
                            }
                            setState(() {});
                          },
                          icon: Icon(controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          iconSize: 22,
                        ),
                        IconButton(
                          onPressed: () async {
                            final vol = controller.value.volume;
                            await controller.setVolume(vol > 0 ? 0 : 1.0);
                            setState(() {});
                          },
                          icon: Icon(controller.value.volume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded),
                          iconSize: 20,
                        ),
                        SizedBox(
                          width: 120,
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
                              onChanged: (v) async {
                                await controller.setVolume(v);
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            crossFadeState: _playerCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
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

  Widget _errorCard(BuildContext context, String error) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(error, style: TextStyle(color: cs.onErrorContainer)),
    );
  }
}

class _QuickActionPill extends StatefulWidget {
  const _QuickActionPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_QuickActionPill> createState() => _QuickActionPillState();
}

class _QuickActionPillState extends State<_QuickActionPill> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Material(
      color: widget.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap == null || _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  widget.onTap!();
                } catch (_) {} finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              else
                Icon(widget.icon, size: 18, color: widget.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(widget.label,
                    style: tt.labelMedium?.copyWith(
                        color: widget.color, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
