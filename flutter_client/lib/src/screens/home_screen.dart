import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../models/system_usage.dart';
import '../services/streaming_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});

  final StreamingApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VideoPlayerController? _videoController;
  StreamStatus? _streamStatus;
  SystemUsage? _systemUsage;
  ServerStatus? _serverStatus;
  List<Chunk> _chunks = <Chunk>[];
  List<AudioFile> _audioFiles = <AudioFile>[];
  String? _error;
  bool _loading = true;
  bool _runningAction = false;
  Timer? _pollTimer;
  final TextEditingController _chunkSearch = TextEditingController();
  final TextEditingController _audioSearch = TextEditingController();
  bool _chunksNewestFirst = true;
  bool _audioLongestFirst = true;

  @override
  void initState() {
    super.initState();
    if (widget.api.config.enableLiveStream) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.api.config.hlsUrl),
      );
      _initializeVideo();
    }
    _refreshData();
    _pollTimer = Timer.periodic(
      Duration(seconds: widget.api.config.refreshSeconds),
      (_) => _refreshData(silent: true),
    );
  }

  Future<void> _initializeVideo() async {
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not initialize HLS player. Check HLS_URL and network access.';
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _chunkSearch.dispose();
    _audioSearch.dispose();
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
      SystemUsage? systemUsage;
      List<Chunk> chunks = <Chunk>[];
      List<AudioFile> audioFiles = <AudioFile>[];

      try {
        serverStatus = await widget.api.getServerStatus();
      } catch (_) {
        warning = 'Could not load server status.';
      }
      try {
        systemUsage = await widget.api.getSystemUsage();
      } catch (_) {
        warning = warning ?? 'Could not load system usage.';
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
        _systemUsage = systemUsage ?? _systemUsage;
        _chunks = chunks;
        _audioFiles = audioFiles;
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
          backgroundColor: const Color(0xFF101A31),
          foregroundColor: Colors.white,
          title: const Text('Streaming Dashboard'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _refreshData,
              icon: const Icon(Icons.refresh),
            ),
          ]),
      body: _loading && _streamStatus == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionHeader('Overview'),
                  _buildOverviewStrip(colors),
                  const SizedBox(height: 12),
                  _buildPlayerCard(),
                  const SizedBox(height: 12),
                  _sectionHeader('Controls'),
                  _buildActionsCard(),
                  const SizedBox(height: 12),
                  _sectionHeader('Live Status'),
                  _buildStatusCard(colors),
                  const SizedBox(height: 12),
                  _sectionHeader('Video Chunks'),
                  _buildChunksToolbar(colors),
                  const SizedBox(height: 12),
                  _buildChunksCard(),
                  const SizedBox(height: 12),
                  _sectionHeader('Audio Library'),
                  _buildAudioToolbar(colors),
                  const SizedBox(height: 12),
                  _buildAudioCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorCard(_error!),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFA5B4FC),
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    );
  }

  Widget _buildOverviewStrip(ColorScheme colors) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip('Chunks', '${_chunks.length}'),
        _chip('Audio files', '${_audioFiles.length}'),
        _chip('Current chunk', _streamStatus?.currentChunk ?? '-'),
        _chip('Current audio', _streamStatus?.currentAudio ?? '-'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF17233F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF283A63)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    if (!widget.api.config.enableLiveStream) {
      return Card(
        color: const Color(0xFF111C36),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live Stream', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Disabled for now. Continue using the dashboard controls below.'),
              const SizedBox(height: 6),
              Text(
                'Set ENABLE_LIVE_STREAM=true to re-enable in builds.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final controller = _videoController;
    final initialized = controller?.value.isInitialized ?? false;
    return Card(
      color: const Color(0xFF111C36),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Stream', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (initialized)
              AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            else
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 8),
            Text(widget.api.config.hlsUrl, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      color: const Color(0xFF111C36),
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
              const Chip(
                label: Text('Generation in progress'),
                backgroundColor: Color(0xFF4C1D1D),
                labelStyle: TextStyle(color: Color(0xFFFCA5A5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme colors) {
    final stream = _streamStatus;
    final usage = _systemUsage;
    return Card(
      color: const Color(0xFF111C36),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Server Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _kv('Current chunk', stream?.currentChunk ?? '-'),
            _kv('Current audio', stream?.currentAudio ?? '-'),
            _kv('Chunks pushed', '${stream?.chunksPushed ?? 0}'),
            _kv('Chunks created', '${stream?.chunksCreatedTotal ?? 0}'),
            const SizedBox(height: 8),
            _kv('CPU', _toPercent(usage?.cpuPercent)),
            _kv('Memory', _toPercent(usage?.memPercent)),
            _kv('GPU', _toPercent(usage?.gpuPercent)),
          ],
        ),
      ),
    );
  }

  Widget _buildChunksToolbar(ColorScheme colors) {
    return Card(
      color: const Color(0xFF111C36),
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
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Search chunk filename',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilterChip(
              selected: _chunksNewestFirst,
              label: Text(_chunksNewestFirst ? 'Newest first' : 'Oldest first'),
              onSelected: (_) => setState(() => _chunksNewestFirst = !_chunksNewestFirst),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChunksCard() {
    return Card(
      color: const Color(0xFF111C36),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recent Chunks', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_visibleChunks.isEmpty)
              const Text('No chunks found')
            else
              ..._visibleChunks.take(40).map((chunk) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(chunk.name),
                  subtitle: Text(
                    '${chunk.createdAt} • ${chunk.sizeMb} MB'
                    '${chunk.daysToExpire != null ? ' • expires in ${chunk.daysToExpire}d' : ''}',
                  ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildAudioToolbar(ColorScheme colors) {
    return Card(
      color: const Color(0xFF111C36),
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
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Search audio filename',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilterChip(
              selected: _audioLongestFirst,
              label: Text(_audioLongestFirst ? 'Longest first' : 'Shortest first'),
              onSelected: (_) => setState(() => _audioLongestFirst = !_audioLongestFirst),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    return Card(
      color: const Color(0xFF111C36),
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
                  color: const Color(0xFF1C2B4D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3B82F6)),
                ),
                child: Text('Now playing: ${_streamStatus!.currentAudio}'),
              ),
            if (_visibleAudio.isEmpty)
              const Text('No audio files found')
            else
              ..._visibleAudio.take(40).map((audio) {
                final subtitle = '${audio.sizeMb} MB'
                    '${audio.durationDisplay != null ? ' • ${audio.durationDisplay}' : ''}';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(audio.name),
                  subtitle: Text(subtitle),
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
          ],
        ),
      ),
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

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(key)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _toPercent(num? value) {
    if (value == null) {
      return '-';
    }
    return '${value.toStringAsFixed(1)}%';
  }
}
