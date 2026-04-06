import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_grid.dart';
import '../widgets/audio_card.dart';
import '../widgets/chunk_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/sources_sheet.dart';

// ── Sort enums ──
enum ChunkSort { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

const _chunkSortLabels = <ChunkSort, String>{
  ChunkSort.dateDesc: 'Date (newest)',
  ChunkSort.dateAsc: 'Date (oldest)',
  ChunkSort.nameAsc: 'Name (A–Z)',
  ChunkSort.nameDesc: 'Name (Z–A)',
  ChunkSort.sizeDesc: 'Size (largest)',
  ChunkSort.sizeAsc: 'Size (smallest)',
};

enum AudioSort { nameAsc, nameDesc, durationAsc, durationDesc, sizeDesc, sizeAsc }

const _audioSortLabels = <AudioSort, String>{
  AudioSort.nameAsc: 'Name (A–Z)',
  AudioSort.nameDesc: 'Name (Z–A)',
  AudioSort.durationAsc: 'Duration (shortest)',
  AudioSort.durationDesc: 'Duration (longest)',
  AudioSort.sizeDesc: 'Size (largest)',
  AudioSort.sizeAsc: 'Size (smallest)',
};

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Chunks state
  final TextEditingController _chunkSearch = TextEditingController();
  ChunkSort _chunkSort = ChunkSort.dateDesc;
  int _chunksPage = 1;
  static const int _chunksPerPage = 6;
  Timer? _chunkSearchDebounce;

  // Audio state
  final TextEditingController _audioSearch = TextEditingController();
  AudioSort _audioSort = AudioSort.durationDesc;
  int _audioPage = 1;
  static const int _audioPerPage = 8;
  Timer? _audioSearchDebounce;

  // For progress bars
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _progressTimer = Timer.periodic(
        const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chunkSearch.dispose();
    _audioSearch.dispose();
    _chunkSearchDebounce?.cancel();
    _audioSearchDebounce?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  String _fmtSec(num? sec) {
    if (sec == null || sec < 0) return '0:00';
    final m = sec ~/ 60;
    final s = sec.toInt() % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _refresh() async {
    ref.read(chunksProvider.notifier).refresh();
    ref.read(audioFilesProvider.notifier).refresh();
    ref.read(streamStatusProvider.notifier).refresh();
  }

  // ── Chunk filtering ──

  List<Chunk> _filterChunks(List<Chunk> chunks, String? nowPlaying) {
    var out = chunks.toList();
    final q = _chunkSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    if (nowPlaying != null) out = out.where((c) => c.name != nowPlaying).toList();

    switch (_chunkSort) {
      case ChunkSort.dateDesc:
        out.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      case ChunkSort.dateAsc:
        out.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
      case ChunkSort.nameAsc:
        out.sort((a, b) => a.name.compareTo(b.name));
      case ChunkSort.nameDesc:
        out.sort((a, b) => b.name.compareTo(a.name));
      case ChunkSort.sizeDesc:
        out.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
      case ChunkSort.sizeAsc:
        out.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
    }
    return out;
  }

  List<AudioFile> _filterAudio(List<AudioFile> audio, String? nowPlaying) {
    var out = audio.toList();
    final q = _audioSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    if (nowPlaying != null) out = out.where((a) => a.name != nowPlaying).toList();

    switch (_audioSort) {
      case AudioSort.nameAsc:
        out.sort((a, b) => a.name.compareTo(b.name));
      case AudioSort.nameDesc:
        out.sort((a, b) => b.name.compareTo(a.name));
      case AudioSort.durationAsc:
        out.sort((a, b) => (a.durationSec ?? 0).compareTo(b.durationSec ?? 0));
      case AudioSort.durationDesc:
        out.sort((a, b) => (b.durationSec ?? 0).compareTo(a.durationSec ?? 0));
      case AudioSort.sizeDesc:
        out.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
      case AudioSort.sizeAsc:
        out.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
    }
    return out;
  }

  List<T> _page<T>(List<T> items, int page, int perPage) {
    if (items.isEmpty) return <T>[];
    final start = (page - 1) * perPage;
    if (start >= items.length || start < 0) return <T>[];
    return items.sublist(start, (start + perPage).clamp(0, items.length));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SectionHeader(
                    title: 'Library',
                    subtitle: 'Chunks & audio files',
                    icon: Icons.video_library_rounded,
                    onRefresh: _refresh,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700),
                      tabs: const [
                        Tab(text: 'Video Chunks', icon: Icon(Icons.movie_rounded, size: 18)),
                        Tab(text: 'Audio', icon: Icon(Icons.audiotrack_rounded, size: 18)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildChunksTab(),
                _buildAudioTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Chunks Tab ──

  Widget _buildChunksTab() {
    final chunksAsync = ref.watch(chunksProvider);
    final streamAsync = ref.watch(streamStatusProvider);
    final nowPlaying = streamAsync.valueOrNull?.currentChunk;
    final api = ref.read(apiProvider);

    return chunksAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoader(count: 4, height: 180),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (allChunks) {
        final st = streamAsync.valueOrNull;
        final filtered = _filterChunks(allChunks, nowPlaying);
        final totalPages = filtered.isEmpty ? 1 : (filtered.length / _chunksPerPage).ceil();
        final page = _chunksPage.clamp(1, totalPages);
        final paged = _page(filtered, page, _chunksPerPage);

        // Now playing chunk
        final npChunk = nowPlaying != null
            ? allChunks.cast<Chunk?>().firstWhere(
                (c) => c?.name == nowPlaying, orElse: () => null)
            : null;

        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Filter bar
              FilterBar(
                searchController: _chunkSearch,
                searchHint: 'Search chunks…',
                onSearchChanged: (_) {
                  _chunkSearchDebounce?.cancel();
                  _chunkSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _chunksPage = 1),
                  );
                },
                sortWidget: SortDropdown<ChunkSort>(
                  value: _chunkSort,
                  labels: _chunkSortLabels,
                  onChanged: (v) => setState(() {
                    _chunkSort = v;
                    _chunksPage = 1;
                  }),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${filtered.length} chunks',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.accentCyan, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Now playing card (full width)
              if (npChunk != null) ...[
                ChunkCard(
                  chunk: npChunk,
                  isNowPlaying: true,
                  progress: _chunkProgress(st),
                  elapsedLabel: _fmtSec(_chunkElapsed(st)),
                  totalLabel: _fmtSec(st?.currentChunkDuration),
                  onPlay: () async {
                    await api.skipToNext();
                    _toast('Skipping…');
                  },
                  onSources: npChunk.hasSources
                      ? () => SourcesSheet.show(context, npChunk)
                      : null,
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 16),
              ],

              // Grid of chunks
              if (paged.isEmpty && npChunk == null)
                _emptyState('No video chunks found')
              else
                AdaptiveGrid(
                  minCrossAxisExtent: 320,
                  mainAxisExtent: 340,
                  children: paged.map((c) {
                    return ChunkCard(
                      chunk: c,
                      onPlay: () async {
                        await api.playChunk(c.name);
                        _toast('Playing "${c.name}"');
                      },
                      onSources: c.hasSources
                          ? () => SourcesSheet.show(context, c)
                          : null,
                    );
                  }).toList(),
                ),

              if (filtered.isNotEmpty)
                PaginationBar(
                  page: page,
                  totalPages: totalPages,
                  onPrev: () => setState(() => _chunksPage = page - 1),
                  onNext: () => setState(() => _chunksPage = page + 1),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Audio Tab ──

  Widget _buildAudioTab() {
    final audioAsync = ref.watch(audioFilesProvider);
    final streamAsync = ref.watch(streamStatusProvider);
    final nowPlaying = streamAsync.valueOrNull?.currentAudio;
    final api = ref.read(apiProvider);

    return audioAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoader(count: 6, height: 80),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (allAudio) {
        final st = streamAsync.valueOrNull;
        final filtered = _filterAudio(allAudio, nowPlaying);
        final totalPages = filtered.isEmpty ? 1 : (filtered.length / _audioPerPage).ceil();
        final page = _audioPage.clamp(1, totalPages);
        final paged = _page(filtered, page, _audioPerPage);

        final npAudio = nowPlaying != null
            ? allAudio.cast<AudioFile?>().firstWhere(
                (a) => a?.name == nowPlaying, orElse: () => null)
            : null;

        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Filter bar
              FilterBar(
                searchController: _audioSearch,
                searchHint: 'Search audio…',
                onSearchChanged: (_) {
                  _audioSearchDebounce?.cancel();
                  _audioSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _audioPage = 1),
                  );
                },
                sortWidget: SortDropdown<AudioSort>(
                  value: _audioSort,
                  labels: _audioSortLabels,
                  onChanged: (v) => setState(() {
                    _audioSort = v;
                    _audioPage = 1;
                  }),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentEmerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${filtered.length} tracks',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.accentEmerald, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Now playing audio
              if (npAudio != null) ...[
                AudioCard(
                  audio: npAudio,
                  isNowPlaying: true,
                  progress: _audioProgress(st),
                  elapsedLabel: _fmtSec(st?.audioPositionSec),
                  totalLabel: _fmtSec(st?.audioTrackDurationSec),
                  onPlay: () async {
                    await api.skipToNextAudio();
                    _toast('Skipping audio…');
                  },
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 12),
              ],

              // Audio list
              if (paged.isEmpty && npAudio == null)
                _emptyState('No audio files found')
              else
                ...paged.asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AudioCard(
                      audio: a,
                      onPlay: () async {
                        await api.playAudio(a.name);
                        _toast('Playing "${a.name}"');
                      },
                      onDelete: () async {
                        await api.deleteAudio(a.path);
                        _toast('Deleted "${a.name}"');
                        ref.read(audioFilesProvider.notifier).refresh();
                      },
                    ).animate().fadeIn(
                      duration: 200.ms,
                      delay: (50 * i).ms,
                    ),
                  );
                }),

              if (filtered.isNotEmpty)
                PaginationBar(
                  page: page,
                  totalPages: totalPages,
                  onPrev: () => setState(() => _audioPage = page - 1),
                  onNext: () => setState(() => _audioPage = page + 1),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ──

  double _chunkProgress(dynamic st) {
    if (st == null) return 0;
    final startedAt = st.currentChunkStartedAt;
    final duration = st.currentChunkDuration;
    if (startedAt == null || duration == null || duration <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return ((now - startedAt.toDouble()) / duration.toDouble()).clamp(0.0, 1.0);
  }

  num? _chunkElapsed(dynamic st) {
    if (st == null) return null;
    final startedAt = st.currentChunkStartedAt;
    final duration = st.currentChunkDuration;
    if (startedAt == null || duration == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return (now - startedAt.toDouble()).clamp(0.0, duration.toDouble());
  }

  double _audioProgress(dynamic st) {
    if (st == null) return 0;
    final pos = st.audioPositionSec;
    final dur = st.audioTrackDurationSec;
    if (pos != null && dur != null && dur > 0) {
      return (pos / dur).clamp(0.0, 1.0);
    }
    return 0;
  }

  Widget _emptyState(String message) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
