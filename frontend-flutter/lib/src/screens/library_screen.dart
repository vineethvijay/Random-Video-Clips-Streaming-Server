import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/filter_bar.dart';
import '../widgets/media_list_tile.dart';
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
  static const int _chunksPerPage = 15;
  Timer? _chunkSearchDebounce;

  // Audio state
  final TextEditingController _audioSearch = TextEditingController();
  AudioSort _audioSort = AudioSort.durationDesc;
  int _audioPage = 1;
  static const int _audioPerPage = 20;
  Timer? _audioSearchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chunkSearch.dispose();
    _audioSearch.dispose();
    _chunkSearchDebounce?.cancel();
    _audioSearchDebounce?.cancel();
    super.dispose();
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

  List<Chunk> _filterChunks(List<Chunk> chunks) {
    var out = chunks.toList();
    final q = _chunkSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
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

  List<AudioFile> _filterAudio(List<AudioFile> audio) {
    var out = audio.toList();
    final q = _audioSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
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

  String _relativeTime(String createdAt) {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return createdAt;
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
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
        child: ShimmerLoader(count: 8, height: 52),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (allChunks) {
        final filtered = _filterChunks(allChunks);
        final totalPages = filtered.isEmpty ? 1 : (filtered.length / _chunksPerPage).ceil();
        final page = _chunksPage.clamp(1, totalPages);
        final paged = _page(filtered, page, _chunksPerPage);

        return ListView(
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
            const SizedBox(height: 12),

            // Chunk list
            if (paged.isEmpty)
              _emptyState('No video chunks found')
            else
              ...paged.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                final isNP = c.name == nowPlaying;
                final sub = '${_relativeTime(c.createdAt)}  ·  ${c.sizeMb} MB'
                    '${c.daysToExpire != null ? '  ·  ${c.daysToExpire}d left' : ''}';
                return MediaListTile(
                  title: c.name,
                  subtitle: sub,
                  icon: Icons.movie_rounded,
                  isNowPlaying: isNP,
                  accentColor: AppTheme.nowPlayingBlue,
                  badges: [
                    if (c.videoCodec != null)
                      BadgeInfo(text: c.videoCodec!.toUpperCase(), color: AppTheme.accentCyan),
                    if (c.width != null && c.height != null)
                      BadgeInfo(text: '${c.width}x${c.height}', color: AppTheme.accentLavender),
                  ],
                  onPlay: () async {
                    if (isNP) {
                      await api.skipToNext();
                      _toast('Skipping…');
                    } else {
                      await api.playChunk(c.name);
                      _toast('Playing "${c.name}"');
                    }
                  },
                  onSources: c.hasSources
                      ? () => SourcesSheet.show(context, c)
                      : null,
                ).animate().fadeIn(duration: 150.ms, delay: (30 * i).ms);
              }),

            if (filtered.isNotEmpty)
              PaginationBar(
                page: page,
                totalPages: totalPages,
                onPrev: () => setState(() => _chunksPage = page - 1),
                onNext: () => setState(() => _chunksPage = page + 1),
                onPageSelected: (p) => setState(() => _chunksPage = p),
              ),
          ],
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
        child: ShimmerLoader(count: 10, height: 52),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (allAudio) {
        final filtered = _filterAudio(allAudio);
        final totalPages = filtered.isEmpty ? 1 : (filtered.length / _audioPerPage).ceil();
        final page = _audioPage.clamp(1, totalPages);
        final paged = _page(filtered, page, _audioPerPage);

        return ListView(
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
            const SizedBox(height: 12),

            // Audio list
            if (paged.isEmpty)
              _emptyState('No audio files found')
            else
              ...paged.asMap().entries.map((entry) {
                final i = entry.key;
                final a = entry.value;
                final isNP = a.name == nowPlaying;
                final sub = '${a.sizeMb} MB'
                    '${a.durationDisplay != null ? '  ·  ${a.durationDisplay}' : ''}';
                return MediaListTile(
                  title: a.name,
                  subtitle: sub,
                  icon: isNP ? Icons.music_note_rounded : Icons.audiotrack_rounded,
                  isNowPlaying: isNP,
                  accentColor: AppTheme.accentEmerald,
                  onPlay: () async {
                    if (isNP) {
                      await api.skipToNextAudio();
                      _toast('Skipping audio…');
                    } else {
                      await api.playAudio(a.name);
                      _toast('Playing "${a.name}"');
                    }
                  },
                  onDelete: () async {
                    await api.deleteAudio(a.path);
                    _toast('Deleted "${a.name}"');
                    ref.read(audioFilesProvider.notifier).refresh();
                  },
                ).animate().fadeIn(duration: 150.ms, delay: (30 * i).ms);
              }),

            if (filtered.isNotEmpty)
              PaginationBar(
                page: page,
                totalPages: totalPages,
                onPrev: () => setState(() => _audioPage = page - 1),
                onNext: () => setState(() => _audioPage = page + 1),
                onPageSelected: (p) => setState(() => _audioPage = p),
              ),
          ],
        );
      },
    );
  }

  // ── Helpers ──

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
