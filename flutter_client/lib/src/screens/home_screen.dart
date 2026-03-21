import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../services/streaming_api.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/primary_meta_row.dart';

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
  /// Live HLS player errors (kept separate so API refresh never wipes them).
  String? _videoError;
  bool _loading = true;
  bool _runningAction = false;
  Timer? _pollTimer;
  final TextEditingController _chunkSearch = TextEditingController();
  final TextEditingController _audioSearch = TextEditingController();
  bool _chunksNewestFirst = true;
  bool _audioLongestFirst = true;
  int _chunksPage = 1;
  int _audioPage = 1;
  static const int _chunksPerPage = 8;
  static const int _audioPerPage = 8;

  @override
  void initState() {
    super.initState();
    if (widget.api.config.enableLiveStream) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.api.config.hlsUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videoController!.addListener(_videoControllerListener);
      _initializeVideo();
    }
    _refreshData();
    _pollTimer = Timer.periodic(
      Duration(seconds: widget.api.config.refreshSeconds),
      (_) => _refreshData(silent: true),
    );
  }

  void _videoControllerListener() {
    final c = _videoController;
    if (c == null || !mounted) {
      return;
    }
    if (c.value.hasError) {
      final msg = c.value.errorDescription;
      setState(() {
        _videoError = (msg != null && msg.isNotEmpty)
            ? msg
            : 'Playback error (check HLS URL and CORS if on web).';
      });
    }
  }

  Future<void> _initializeVideo() async {
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    setState(() {
      _videoError = null;
    });
    try {
      await controller.initialize();
      if (!mounted) {
        return;
      }
      await controller.setLooping(true);
      try {
        await controller.play();
      } catch (e) {
        if (kIsWeb) {
          setState(() {
            _videoError =
                'Autoplay may be blocked — use the Play button below. ($e)';
          });
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _videoError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _videoError =
              'Could not load live stream. On web, ensure HLS is served with CORS and use http/https consistently.\n$e';
        });
      }
    }
  }

  Future<void> _retryLiveVideo() async {
    _videoController?.removeListener(_videoControllerListener);
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.api.config.hlsUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _videoController!.addListener(_videoControllerListener);
    await _initializeVideo();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _chunkSearch.dispose();
    _audioSearch.dispose();
    _videoController?.removeListener(_videoControllerListener);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _refreshData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      String? warning;
      final streamStatus = await widget.api.getStreamStatus();
      ServerStatus? serverStatus;
      List<Chunk> chunks = <Chunk>[];
      List<AudioFile> audioFiles = <AudioFile>[];

      try {
        serverStatus = await widget.api.getServerStatus();
      } catch (_) {
        warning = 'Could not load server status.';
      }
      try {
        chunks = await widget.api.getChunks(limit: 200);
      } catch (_) {
        warning = warning ?? 'Could not load chunks.';
      }
      try {
        audioFiles = await widget.api.getAudioFiles(limit: 300);
      } catch (_) {
        warning = warning ?? 'Could not load audio list.';
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _streamStatus = streamStatus;
        _serverStatus = serverStatus ?? _serverStatus;
        _chunks = chunks;
        _audioFiles = audioFiles;
        _chunksPage = 1;
        _audioPage = 1;
        _loading = false;
        _error = warning;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_runningAction) {
      return;
    }
    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      await action();
      await _refreshData(silent: true);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  List<Chunk> get _visibleChunks {
    var out = _chunks;
    final q = _chunkSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    out.sort((a, b) => _chunksNewestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    return out;
  }

  List<AudioFile> get _visibleAudio {
    var out = _audioFiles;
    final q = _audioSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    out = out.where((a) => a.name != _streamStatus?.currentAudio).toList();
    out.sort((a, b) {
      final ad = a.durationSec ?? 0;
      final bd = b.durationSec ?? 0;
      return _audioLongestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
    });
    return out;
  }

  List<T> _pageItems<T>(List<T> items, int page, int perPage) {
    if (items.isEmpty) return <T>[];
    final start = (page - 1) * perPage;
    if (start >= items.length || start < 0) return <T>[];
    final end = (start + perPage).clamp(0, items.length);
    return items.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading && _streamStatus == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                  DashboardHeader(
                    title: 'Streaming Dashboard',
                    onRefresh: _loading ? null : _refreshData,
                  ),
                  _sectionHeader(context, 'Overview'),
                  _buildOverviewStrip(context),
                  const SizedBox(height: 12),
                  _buildPlayerCard(),
                  const SizedBox(height: 12),
                  _sectionHeader(context, 'Controls'),
                  _buildActionsCard(),
                  const SizedBox(height: 12),
                  _sectionHeader(context, 'Video Chunks'),
                  _buildChunksToolbar(context),
                  const SizedBox(height: 12),
                  _buildChunksCard(),
                  const SizedBox(height: 12),
                  _sectionHeader(context, 'Audio Library'),
                  _buildAudioToolbar(context),
                  const SizedBox(height: 12),
                  _buildAudioCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorCard(_error!),
                  ],
                ],
                ),
              ),
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
            ),
      ),
    );
  }

  Widget _buildOverviewStrip(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip(context, 'Chunks', '${_chunks.length}'),
        _chip(context, 'Audio files', '${_audioFiles.length}'),
        _chip(context, 'Current chunk', _streamStatus?.currentChunk ?? '-'),
        _chip(context, 'Current audio', _streamStatus?.currentAudio ?? '-'),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          style: base?.copyWith(color: cs.onSurfaceVariant),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: base?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    if (!widget.api.config.enableLiveStream) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live Stream', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Live stream player is off by default.'),
              const SizedBox(height: 6),
              Text(
                'Rebuild with ENABLE_LIVE_STREAM=true if you want the embedded HLS player.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final controller = _videoController;
    final initialized = controller?.value.isInitialized ?? false;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Live Stream', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (initialized)
                  IconButton.filledTonal(
                    tooltip: controller!.value.isPlaying ? 'Pause' : 'Play',
                    onPressed: () async {
                      if (controller.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                      setState(() {});
                    },
                    icon: Icon(
                      controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_videoError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _videoError!,
                  style: tt.bodySmall?.copyWith(color: cs.onErrorContainer),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _retryLiveVideo,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                  if (initialized && kIsWeb)
                    FilledButton.icon(
                      onPressed: () async {
                        await controller?.play();
                        setState(() {});
                      },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Play'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (initialized)
              AspectRatio(
                aspectRatio: controller!.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            else if (_videoError == null)
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 8),
            SelectableText(
              widget.api.config.hlsUrl,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Web uses HLS.js for .m3u8. The stream host must allow CORS for playlists and segments.',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _runningAction ? null : () => _runAction(widget.api.skipToNext),
              icon: const Icon(Icons.skip_next),
              label: const Text('Skip Video'),
            ),
            ElevatedButton.icon(
              onPressed: _runningAction ? null : () => _runAction(widget.api.skipToNextAudio),
              icon: const Icon(Icons.music_note),
              label: const Text('Skip Audio'),
            ),
            ElevatedButton.icon(
              onPressed: _runningAction ? null : () => _runAction(widget.api.generateChunks),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Generate Chunks'),
            ),
            if (_serverStatus?.generationInProgress == true)
              Chip(
                label: const Text('Generation in progress'),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChunksToolbar(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _chunkSearch,
                onChanged: (_) => setState(() => _chunksPage = 1),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Search chunk filename',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilterChip(
              selected: _chunksNewestFirst,
              label: Text(_chunksNewestFirst ? 'Newest first' : 'Oldest first'),
              onSelected: (_) => setState(() {
                _chunksNewestFirst = !_chunksNewestFirst;
                _chunksPage = 1;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChunksCard() {
    final visible = _visibleChunks;
    final totalPages = visible.isEmpty ? 1 : (visible.length / _chunksPerPage).ceil();
    final page = _chunksPage.clamp(1, totalPages);
    final paged = _pageItems(visible, page, _chunksPerPage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recent Chunks', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              const Text('No chunks found')
            else
              ...paged.map((chunk) {
                final meta =
                    '${chunk.createdAt} • ${chunk.sizeMb} MB'
                    '${chunk.daysToExpire != null ? ' • expires in ${chunk.daysToExpire}d' : ''}';
                return PrimaryMetaRow(
                  primary: chunk.name,
                  meta: meta,
                  trailing: TextButton(
                    onPressed: _runningAction
                        ? null
                        : () => _runAction(() async {
                            await widget.api.playChunk(chunk.name);
                            _toast('Chunk "${chunk.name}" queued to play next');
                          }),
                    child: const Text('Play Next'),
                  ),
                );
              }),
            if (visible.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildPager(
                page: page,
                totalPages: totalPages,
                onPrev: page > 1 ? () => setState(() => _chunksPage = page - 1) : null,
                onNext: page < totalPages ? () => setState(() => _chunksPage = page + 1) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioToolbar(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _audioSearch,
                onChanged: (_) => setState(() => _audioPage = 1),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Search audio filename',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilterChip(
              selected: _audioLongestFirst,
              label: Text(_audioLongestFirst ? 'Longest first' : 'Shortest first'),
              onSelected: (_) => setState(() {
                _audioLongestFirst = !_audioLongestFirst;
                _audioPage = 1;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    final visible = _visibleAudio;
    final totalPages = visible.isEmpty ? 1 : (visible.length / _audioPerPage).ceil();
    final page = _audioPage.clamp(1, totalPages);
    final paged = _pageItems(visible, page, _audioPerPage);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_streamStatus?.currentAudio != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                  ),
                ),
                child: Text(
                  'Now playing: ${_streamStatus!.currentAudio}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (visible.isEmpty)
              const Text('No audio files found')
            else
              ...paged.map((audio) {
                final meta = '${audio.sizeMb} MB'
                    '${audio.durationDisplay != null ? ' • ${audio.durationDisplay}' : ''}';
                return PrimaryMetaRow(
                  primary: audio.name,
                  meta: meta,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(() async {
                                await widget.api.playAudio(audio.name);
                                _toast('Audio "${audio.name}" queued');
                              }),
                        child: const Text('Play'),
                      ),
                      TextButton(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(() async {
                                await widget.api.deleteAudio(audio.path);
                                _toast('Deleted "${audio.name}"');
                              }),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              }),
            if (visible.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildPager(
                page: page,
                totalPages: totalPages,
                onPrev: page > 1 ? () => setState(() => _audioPage = page - 1) : null,
                onNext: page < totalPages ? () => setState(() => _audioPage = page + 1) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPager({
    required int page,
    required int totalPages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Row(
      children: [
        OutlinedButton(onPressed: onPrev, child: const Text('Prev')),
        const SizedBox(width: 10),
        Text('Page $page of $totalPages'),
        const SizedBox(width: 10),
        OutlinedButton(onPressed: onNext, child: const Text('Next')),
      ],
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error),
      ),
    );
  }

}
