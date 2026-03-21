import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../services/streaming_api.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_progress_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/sources_sheet.dart';
import '../widgets/stat_card.dart';

// ──────────────────────────────────────────────────────────────────
// Sort options
// ──────────────────────────────────────────────────────────────────
enum _ChunkSort { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

const _chunkSortLabels = <_ChunkSort, String>{
  _ChunkSort.dateDesc: 'Date (newest)',
  _ChunkSort.dateAsc: 'Date (oldest)',
  _ChunkSort.nameAsc: 'Name (A–Z)',
  _ChunkSort.nameDesc: 'Name (Z–A)',
  _ChunkSort.sizeDesc: 'Size (largest)',
  _ChunkSort.sizeAsc: 'Size (smallest)',
};

enum _AudioSort { nameAsc, nameDesc, durationAsc, durationDesc, sizeDesc, sizeAsc }

const _audioSortLabels = <_AudioSort, String>{
  _AudioSort.nameAsc: 'Name (A–Z)',
  _AudioSort.nameDesc: 'Name (Z–A)',
  _AudioSort.durationAsc: 'Duration (shortest)',
  _AudioSort.durationDesc: 'Duration (longest)',
  _AudioSort.sizeDesc: 'Size (largest)',
  _AudioSort.sizeAsc: 'Size (smallest)',
};

// ──────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final StreamingApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VideoPlayerController? _videoController;
  StreamStatus? _streamStatus;
  ServerStatus? _serverStatus;
  List<Chunk> _chunks = <Chunk>[];
  List<AudioFile> _audioFiles = <AudioFile>[];
  String? _error;
  String? _videoError;
  bool _loading = true;
  bool _runningAction = false;
  bool _playerCollapsed = true;
  Timer? _pollTimer;
  Timer? _progressTimer;

  // Chunks
  final TextEditingController _chunkSearch = TextEditingController();
  _ChunkSort _chunkSort = _ChunkSort.dateDesc;
  int _chunksPage = 1;
  static const int _chunksPerPage = 5;

  // Audio
  final TextEditingController _audioSearch = TextEditingController();
  final TextEditingController _audioDurMin = TextEditingController();
  final TextEditingController _audioDurMax = TextEditingController();
  _AudioSort _audioSort = _AudioSort.durationDesc;
  int _audioPage = 1;
  static const int _audioPerPage = 4;

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    if (widget.api.config.enableLiveStream) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.api.config.hlsUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )..addListener(_videoListener);
      _initializeVideo();
    }
    _refreshData();
    _pollTimer = Timer.periodic(
      Duration(seconds: widget.api.config.refreshSeconds),
      (_) => _refreshData(silent: true),
    );
    _progressTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _progressTimer?.cancel();
    _chunkSearch.dispose();
    _audioSearch.dispose();
    _audioDurMin.dispose();
    _audioDurMax.dispose();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  // ── Video helpers ──

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
      try {
        await c.play();
      } catch (e) {
        if (kIsWeb) {
          setState(() => _videoError = 'Autoplay may be blocked ($e)');
        }
      }
      if (mounted) setState(() => _videoError = null);
    } catch (e) {
      if (mounted) setState(() => _videoError = 'Could not load stream.\n$e');
    }
  }

  Future<void> _retryVideo() async {
    _videoController?.removeListener(_videoListener);
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.api.config.hlsUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..addListener(_videoListener);
    await _initializeVideo();
    if (mounted) setState(() {});
  }

  // ── Data ──

  Future<void> _refreshData({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final streamStatus = await widget.api.getStreamStatus();
      ServerStatus? serverStatus;
      List<Chunk> chunks = <Chunk>[];
      List<AudioFile> audio = <AudioFile>[];
      String? warn;
      try { serverStatus = await widget.api.getServerStatus(); } catch (_) { warn = 'Could not load server status.'; }
      try { chunks = await widget.api.getChunks(limit: 200); } catch (_) { warn ??= 'Could not load chunks.'; }
      try { audio = await widget.api.getAudioFiles(limit: 300); } catch (_) { warn ??= 'Could not load audio.'; }
      if (!mounted) return;
      setState(() {
        _streamStatus = streamStatus;
        _serverStatus = serverStatus ?? _serverStatus;
        _chunks = chunks;
        _audioFiles = audio;
        _loading = false;
        _error = warn;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _tick() { if (mounted) setState(() {}); }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_runningAction) return;
    setState(() { _runningAction = true; _error = null; });
    try {
      await action();
      await _refreshData(silent: true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  // ── Filtering / sorting ──

  List<Chunk> get _visibleChunks {
    var out = _chunks.toList();
    final q = _chunkSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    // Remove now-playing from the list — it's pinned separately
    final np = _streamStatus?.currentChunk;
    if (np != null) out = out.where((c) => c.name != np).toList();

    switch (_chunkSort) {
      case _ChunkSort.dateDesc:
        out.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      case _ChunkSort.dateAsc:
        out.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
      case _ChunkSort.nameAsc:
        out.sort((a, b) => a.name.compareTo(b.name));
      case _ChunkSort.nameDesc:
        out.sort((a, b) => b.name.compareTo(a.name));
      case _ChunkSort.sizeDesc:
        out.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
      case _ChunkSort.sizeAsc:
        out.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
    }
    return out;
  }

  List<AudioFile> get _visibleAudio {
    var out = _audioFiles.toList();
    final q = _audioSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    // Duration filter
    final minSec = _parseDuration(_audioDurMin.text);
    final maxSec = _parseDuration(_audioDurMax.text);
    if (minSec != null || maxSec != null) {
      out = out.where((a) {
        final d = a.durationSec;
        if (d == null) return false;
        if (minSec != null && d < minSec) return false;
        if (maxSec != null && d > maxSec) return false;
        return true;
      }).toList();
    }
    // Remove now-playing
    final np = _streamStatus?.currentAudio;
    if (np != null) out = out.where((a) => a.name != np).toList();

    switch (_audioSort) {
      case _AudioSort.nameAsc:
        out.sort((a, b) => a.name.compareTo(b.name));
      case _AudioSort.nameDesc:
        out.sort((a, b) => b.name.compareTo(a.name));
      case _AudioSort.durationAsc:
        out.sort((a, b) => (a.durationSec ?? 0).compareTo(b.durationSec ?? 0));
      case _AudioSort.durationDesc:
        out.sort((a, b) => (b.durationSec ?? 0).compareTo(a.durationSec ?? 0));
      case _AudioSort.sizeDesc:
        out.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
      case _AudioSort.sizeAsc:
        out.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
    }
    return out;
  }

  int? _parseDuration(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(s);
    if (m != null) {
      final h = m.group(3) != null ? int.parse(m.group(1)!) : 0;
      final min = m.group(3) != null ? int.parse(m.group(2)!) : int.parse(m.group(1)!);
      final sec = m.group(3) != null ? int.parse(m.group(3)!) : int.parse(m.group(2)!);
      return h * 3600 + min * 60 + sec;
    }
    final n = int.tryParse(s);
    return n != null && n >= 0 ? n : null;
  }

  List<T> _page<T>(List<T> items, int page, int perPage) {
    if (items.isEmpty) return <T>[];
    final start = (page - 1) * perPage;
    if (start >= items.length || start < 0) return <T>[];
    return items.sublist(start, (start + perPage).clamp(0, items.length));
  }

  // ── Progress calculations ──

  double _chunkProgress() {
    final st = _streamStatus;
    if (st == null) return 0;
    final startedAt = st.currentChunkStartedAt;
    final duration = st.currentChunkDuration;
    if (startedAt == null || duration == null || duration <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final elapsed = now - startedAt.toDouble();
    return (elapsed / duration.toDouble()).clamp(0.0, 1.0);
  }

  String _fmtSec(num? sec) {
    if (sec == null || sec < 0) return '0:00';
    final m = (sec ~/ 60);
    final s = (sec.toInt() % 60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  double _audioProgress() {
    final st = _streamStatus;
    if (st == null) return 0;
    final pos = st.audioPositionSec;
    final dur = st.audioTrackDurationSec;
    if (pos != null && dur != null && dur > 0) {
      return (pos / dur).clamp(0.0, 1.0);
    }
    return 0;
  }

  // ── BUILD ──

  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget? body;
    if (_loading && _streamStatus == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      switch (_navIndex) {
        case 0:
          body = RefreshIndicator(
            onRefresh: _refreshData,
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 16),
                  _buildOverviewStrip(context),
                  const SizedBox(height: 16),
                  _buildPlayerCard(context),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(context, _error!),
                  ],
                ],
              ),
            ),
          );
          break;
        case 1:
          body = RefreshIndicator(
            onRefresh: _refreshData,
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildHeader(context, title: 'Video Chunks'),
                  const SizedBox(height: 16),
                  _buildChunksSection(context),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(context, _error!),
                  ],
                ],
              ),
            ),
          );
          break;
        case 2:
          body = RefreshIndicator(
            onRefresh: _refreshData,
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildHeader(context, title: 'Audio Library'),
                  const SizedBox(height: 16),
                  _buildAudioSection(context),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(context, _error!),
                  ],
                ],
              ),
            ),
          );
          break;
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: body!),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (v) => setState(() => _navIndex = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Audio',
          ),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(BuildContext context, {String title = 'Streaming Dashboard'}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [
              cs.primary.withValues(alpha: 0.3),
              cs.tertiary.withValues(alpha: 0.2),
            ]),
            border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.play_circle_fill_rounded, color: cs.primary, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: tt.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        IconButton.filledTonal(
          onPressed: _loading ? null : _refreshData,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ── Overview strip ──

  Widget _buildOverviewStrip(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatCard(
          label: 'Chunks',
          value: '${_chunks.length}',
          icon: Icons.video_library_rounded,
          gradientStart: AppTheme.accentCyan.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentCyan.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Audio Files',
          value: '${_audioFiles.length}',
          icon: Icons.library_music_rounded,
          gradientStart: AppTheme.accentEmerald.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentEmerald.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Now Playing',
          value: _streamStatus?.currentChunk ?? '—',
          icon: Icons.live_tv_rounded,
          gradientStart: AppTheme.nowPlayingBlue.withValues(alpha: 0.15),
          gradientEnd: AppTheme.nowPlayingBlue.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Now Audio',
          value: _streamStatus?.currentAudio ?? '—',
          icon: Icons.music_note_rounded,
          gradientStart: AppTheme.accentAmber.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentAmber.withValues(alpha: 0.05),
        ),
      ],
    );
  }

  // ── Live stream player ──

  Widget _buildPlayerCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!widget.api.config.enableLiveStream) {
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
                  Icon(
                    _playerCollapsed ? Icons.play_arrow_rounded : Icons.expand_more_rounded,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('Live Stream',
                      style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentEmerald)),
                  const Spacer(),
                  if (initialized && controller!.value.isPlaying)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentEmerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('LIVE',
                          style: tt.labelSmall?.copyWith(
                              color: AppTheme.accentEmerald,
                              fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ),
          // Body
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
                if (initialized)
                  GestureDetector(
                    onTap: () async {
                      if (controller!.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                      setState(() {});
                    },
                    child: AspectRatio(
                      aspectRatio: controller!.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(controller),
                          Positioned.fill(
                            child: Container(color: Colors.transparent),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_videoError == null)
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (initialized)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            if (controller!.value.isPlaying) {
                              await controller.pause();
                            } else {
                              await controller.play();
                            }
                            setState(() {});
                          },
                          icon: Icon(controller!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          iconSize: 22,
                        ),
                        IconButton(
                          onPressed: () async {
                            final vol = controller!.value.volume;
                            await controller.setVolume(vol > 0 ? 0 : 1.0);
                            setState(() {});
                          },
                          icon: Icon(
                            controller!.value.volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                          ),
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
                              value: controller!.value.volume,
                              onChanged: (v) async {
                                await controller!.setVolume(v);
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
            crossFadeState: _playerCollapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  // CHUNKS SECTION
  // ───────────────────────────────────────────────

  Widget _buildChunksSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final visible = _visibleChunks;
    final totalPages = visible.isEmpty ? 1 : (visible.length / _chunksPerPage).ceil();
    final page = _chunksPage.clamp(1, totalPages);
    final paged = _page(visible, page, _chunksPerPage);
    final nowPlaying = _streamStatus?.currentChunk;
    final npChunk = nowPlaying != null
        ? _chunks.cast<Chunk?>().firstWhere((c) => c?.name == nowPlaying,
            orElse: () => null)
        : null;
    final totalCount = _chunks.where((c) => c.name != nowPlaying).length;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.video_library_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Video Chunks',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                // Skip next
                FilledButton.tonalIcon(
                  onPressed: _runningAction
                      ? null
                      : () => _run(() async {
                            await widget.api.skipToNext();
                            _toast('Skipping to next video…');
                          }),
                  icon: const Icon(Icons.skip_next_rounded, size: 16),
                  label: const Text('Play Next'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentEmerald.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.accentEmerald,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    visible.length == totalCount
                        ? '$totalCount Chunks'
                        : '${visible.length} of $totalCount',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _chunkSearch,
                    onChanged: (_) => setState(() => _chunksPage = 1),
                    style: tt.bodySmall,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Filter by filename…',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                _sortDropdown<_ChunkSort>(
                  value: _chunkSort,
                  labels: _chunkSortLabels,
                  onChanged: (v) => setState(() {
                    _chunkSort = v;
                    _chunksPage = 1;
                  }),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),

          // Now-playing row
          if (npChunk != null) _buildNowPlayingChunkRow(context, npChunk),

          // Chunk rows
          if (paged.isEmpty && npChunk == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No chunks found',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...paged.map((c) => _buildChunkRow(context, c)),

          // Pagination
          if (visible.isNotEmpty)
            _buildPagination(
              page: page,
              totalPages: totalPages,
              onPrev: page > 1 ? () => setState(() => _chunksPage = page - 1) : null,
              onNext: page < totalPages ? () => setState(() => _chunksPage = page + 1) : null,
            ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingChunkRow(BuildContext context, Chunk chunk) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = _chunkProgress();
    final st = _streamStatus;
    final elapsed = st?.currentChunkStartedAt != null && st?.currentChunkDuration != null
        ? (DateTime.now().millisecondsSinceEpoch / 1000 - st!.currentChunkStartedAt!.toDouble())
            .clamp(0.0, st.currentChunkDuration!.toDouble())
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.nowPlayingBlue.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: AppTheme.nowPlayingBlue, width: 3),
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(chunk.name,
                        style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: cs.onSurface)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.nowPlayingBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('NOW PLAYING ▶',
                          style: tt.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 9)),
                    ),
                    if (chunk.hasSources)
                      InkWell(
                        onTap: () => SourcesSheet.show(context, chunk),
                        child: Text('Sources',
                            style: tt.labelSmall?.copyWith(
                                color: cs.primary, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              _pushButton(context, chunk.name, isChunk: true),
            ],
          ),
          if (elapsed != null) ...[
            const SizedBox(height: 8),
            AnimatedProgressBar(
              progress: progress,
              elapsedLabel: _fmtSec(elapsed),
              totalLabel: _fmtSec(st?.currentChunkDuration),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChunkRow(BuildContext context, Chunk chunk) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(chunk.name,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (chunk.hasSources)
                      InkWell(
                        onTap: () => SourcesSheet.show(context, chunk),
                        child: Text('Sources',
                            style: tt.labelSmall?.copyWith(
                                color: cs.primary, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  chunk.metaSummary,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _pushButton(context, chunk.name, isChunk: true),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  // AUDIO SECTION
  // ───────────────────────────────────────────────

  Widget _buildAudioSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final visible = _visibleAudio;
    final totalPages = visible.isEmpty ? 1 : (visible.length / _audioPerPage).ceil();
    final page = _audioPage.clamp(1, totalPages);
    final paged = _page(visible, page, _audioPerPage);
    final nowPlaying = _streamStatus?.currentAudio;
    final npAudio = nowPlaying != null
        ? _audioFiles.cast<AudioFile?>().firstWhere((a) => a?.name == nowPlaying,
            orElse: () => null)
        : null;
    final totalCount = _audioFiles.where((a) => a.name != nowPlaying).length;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.library_music_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Audio Files',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_audioFiles.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _runningAction
                        ? null
                        : () => _run(() async {
                              await widget.api.skipToNextAudio();
                              _toast('Skipping to next audio…');
                            }),
                    icon: const Icon(Icons.skip_next_rounded, size: 16),
                    label: const Text('Next Audio'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentEmerald.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.accentEmerald,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    visible.length == totalCount
                        ? '$totalCount files'
                        : '${visible.length} of $totalCount',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _audioSearch,
                    onChanged: (_) => setState(() => _audioPage = 1),
                    style: tt.bodySmall,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Filter by filename…',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _audioDurMin,
                    onChanged: (_) => setState(() => _audioPage = 1),
                    style: tt.bodySmall,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Min (2:30)',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _audioDurMax,
                    onChanged: (_) => setState(() => _audioPage = 1),
                    style: tt.bodySmall,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Max (5:00)',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                _sortDropdown<_AudioSort>(
                  value: _audioSort,
                  labels: _audioSortLabels,
                  onChanged: (v) => setState(() {
                    _audioSort = v;
                    _audioPage = 1;
                  }),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),

          // Now-playing audio
          if (npAudio != null) _buildNowPlayingAudioRow(context, npAudio),

          // Audio rows
          if (paged.isEmpty && npAudio == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No audio files found',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...paged.map((a) => _buildAudioRow(context, a)),

          // Pagination
          if (visible.isNotEmpty)
            _buildPagination(
              page: page,
              totalPages: totalPages,
              onPrev: page > 1 ? () => setState(() => _audioPage = page - 1) : null,
              onNext: page < totalPages ? () => setState(() => _audioPage = page + 1) : null,
            ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingAudioRow(BuildContext context, AudioFile audio) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = _audioProgress();
    final st = _streamStatus;
    final pos = st?.audioPositionSec;
    final dur = st?.audioTrackDurationSec;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.nowPlayingBlue.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: AppTheme.nowPlayingBlue, width: 3),
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(audio.name,
                        style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: cs.onSurface)),
                    if (audio.durationDisplay != null)
                      Text(audio.durationDisplay!,
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.nowPlayingBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('NOW PLAYING',
                          style: tt.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 9)),
                    ),
                  ],
                ),
              ),
              _pushButton(context, audio.name, isChunk: false),
            ],
          ),
          if (pos != null && dur != null && dur > 0) ...[
            const SizedBox(height: 8),
            AnimatedProgressBar(
              progress: progress,
              elapsedLabel: _fmtSec(pos),
              totalLabel: _fmtSec(dur),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioRow(BuildContext context, AudioFile audio) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(audio.name,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  '${audio.sizeMb} MB${audio.durationDisplay != null ? ' · ${audio.durationDisplay}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _pushButton(context, audio.name, isChunk: false),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _runningAction
                ? null
                : () => _run(() async {
                      await widget.api.deleteAudio(audio.path);
                      _toast('Deleted "${audio.name}"');
                    }),
            icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: AppTheme.accentRose.withValues(alpha: 0.8)),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ──

  Widget _pushButton(BuildContext context, String name,
      {required bool isChunk}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: TextButton(
        onPressed: _runningAction
            ? null
            : () => _run(() async {
                  if (isChunk) {
                    await widget.api.playChunk(name);
                    _toast('Pushed "$name" to stream');
                  } else {
                    await widget.api.playAudio(name);
                    _toast('Pushed "$name" to stream');
                  }
                }),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          foregroundColor: cs.onSurface,
          textStyle: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        child: const Text('Push to stream'),
      ),
    );
  }

  Widget _sortDropdown<T extends Enum>({
    required T value,
    required Map<T, String> labels,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        style: tt.bodySmall?.copyWith(color: cs.onSurface),
        icon: Icon(Icons.unfold_more_rounded, size: 16, color: cs.onSurfaceVariant),
        items: labels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _buildPagination({
    required int page,
    required int totalPages,
    VoidCallback? onPrev,
    VoidCallback? onNext,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Page $page of $totalPages',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(error,
          style: TextStyle(color: cs.onErrorContainer)),
    );
  }
}
