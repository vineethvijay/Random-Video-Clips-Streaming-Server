import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/platform_badge.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  // Models state
  String _modelSearch = '';
  String _modelSortBy = 'count';
  bool _modelSortAsc = false;
  String _filterPlatform = 'all';
  int _modelsPage = 1;
  static const int _modelsPerPage = 20;

  // Audio state
  bool _audioCollapsed = true;
  int _audioPage = 1;
  static const int _audioPerPage = 12;

  List<Map<String, dynamic>> _allModels(Map<String, dynamic> stats) {
    final pc = stats['play_counts'] as Map<String, dynamic>? ?? {};
    final raw = pc['models'] as List<dynamic>? ?? [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _filteredModels(Map<String, dynamic> stats) {
    var out = _allModels(stats);
    if (_filterPlatform != 'all') {
      out = out.where((m) => m['platform'] == _filterPlatform).toList();
    }
    if (_modelSearch.isNotEmpty) {
      final q = _modelSearch.toLowerCase();
      out = out.where((m) {
        final u = (m['username'] ?? '').toString().toLowerCase();
        final c = (m['channel'] ?? '').toString().toLowerCase();
        return u.contains(q) || c.contains(q);
      }).toList();
    }
    out.sort((a, b) {
      dynamic va, vb;
      switch (_modelSortBy) {
        case 'count':
          va = a['count'] ?? 0; vb = b['count'] ?? 0;
        case 'username':
          va = (a['username'] ?? '').toString().toLowerCase();
          vb = (b['username'] ?? '').toString().toLowerCase();
        case 'channel':
          va = (a['channel'] ?? '').toString().toLowerCase();
          vb = (b['channel'] ?? '').toString().toLowerCase();
        default:
          va = a['count'] ?? 0; vb = b['count'] ?? 0;
      }
      int cmp;
      if (va is String) {
        cmp = va.compareTo(vb as String);
      } else {
        cmp = (va as num).compareTo(vb as num);
      }
      if (cmp == 0) cmp = ((b['count'] ?? 0) as num).compareTo((a['count'] ?? 0) as num);
      return _modelSortAsc ? cmp : -cmp;
    });
    return out;
  }

  void _setModelSort(String field) {
    setState(() {
      if (_modelSortBy == field) {
        _modelSortAsc = !_modelSortAsc;
      } else {
        _modelSortBy = field;
        _modelSortAsc = field == 'username' || field == 'channel';
      }
      _modelsPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      body: SafeArea(
        child: statsAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const ShimmerStatRow(count: 3),
              const SizedBox(height: 16),
              ShimmerLoader(count: 4, height: 80),
            ]),
          ),
          error: (e, _) => Center(child: Text('$e')),
          data: (stats) {
            final stream = stats['stream_stats'] as Map<String, dynamic>? ?? {};
            final pcAudio = (stats['play_counts'] as Map<String, dynamic>?)?['audio'] as List<dynamic>? ?? [];
            final models = _filteredModels(stats);
            final allCount = _allModels(stats).length;

            return RefreshIndicator(
              onRefresh: () async => ref.read(statsProvider.notifier).refresh(),
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    SectionHeader(
                      title: 'Stats',
                      subtitle: 'Play counts & stream data',
                      icon: Icons.bar_chart_rounded,
                      onRefresh: () => ref.read(statsProvider.notifier).refresh(),
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
                    const SizedBox(height: 20),
                    _buildStreamStats(context, stream),
                    const SizedBox(height: 20),
                    _buildModelsSection(context, models, allCount),
                    const SizedBox(height: 16),
                    _buildAudioSection(context, pcAudio),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStreamStats(BuildContext context, Map<String, dynamic> stream) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatCard(
          label: 'Time Played',
          value: '${stream['time_played'] ?? '—'}',
          icon: Icons.timer_rounded,
          gradientStart: AppTheme.accentCyan.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentCyan.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Chunks Pushed',
          value: '${stream['chunks_pushed'] ?? '—'}',
          icon: Icons.upload_rounded,
          gradientStart: AppTheme.accentEmerald.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentEmerald.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Chunks Created',
          value: '${stream['chunks_created_total'] ?? '—'}',
          icon: Icons.layers_rounded,
          gradientStart: AppTheme.accentAmber.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentAmber.withValues(alpha: 0.05),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _buildModelsSection(BuildContext context, List<Map<String, dynamic>> models, int allCount) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totalPages = models.isEmpty ? 1 : (models.length / _modelsPerPage).ceil();
    final page = _modelsPage.clamp(1, totalPages);
    final start = (page - 1) * _modelsPerPage;
    final end = (start + _modelsPerPage).clamp(0, models.length);
    final pageModels = models.isEmpty ? <Map<String, dynamic>>[] : models.sublist(start, end);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.people_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Models', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(
                  '(${models.length}${models.length != allCount ? '/$allCount' : ''})',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _sortChip(context, 'Plays', 'count'),
                _sortChip(context, 'Name', 'username'),
                _sortChip(context, 'Channel', 'channel'),
                const SizedBox(width: 4),
                _platformFilter(context),
                SizedBox(
                  width: 160,
                  child: TextField(
                    onChanged: (v) => setState(() { _modelSearch = v; _modelsPage = 1; }),
                    style: tt.bodySmall,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search_rounded, size: 16),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),

          // Models grid
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No model stats yet',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  if (!isWide) {
                    return Column(
                      children: pageModels.asMap().entries.map((e) =>
                        _modelTile(context, e.value, e.key)
                      ).toList(),
                    );
                  }
                  // Two columns
                  final left = <Widget>[];
                  final right = <Widget>[];
                  for (var i = 0; i < pageModels.length; i++) {
                    (i % 2 == 0 ? left : right).add(_modelTile(context, pageModels[i], i));
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: left)),
                        const SizedBox(width: 8),
                        Expanded(child: Column(children: right)),
                      ],
                    ),
                  );
                },
              ),
            ),

          if (totalPages > 1)
            PaginationBar(
              page: page,
              totalPages: totalPages,
              onPrev: () => setState(() => _modelsPage = page - 1),
              onNext: () => setState(() => _modelsPage = page + 1),
            ),
          const SizedBox(height: 4),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  Widget _sortChip(BuildContext context, String label, String field) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final active = _modelSortBy == field;
    final arrow = active ? (_modelSortAsc ? ' ↑' : ' ↓') : '';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _setModelSort(field),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: active ? cs.primary : cs.surfaceContainerHighest,
        ),
        child: Text('$label$arrow',
            style: tt.labelSmall?.copyWith(
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }

  Widget _platformFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: DropdownButton<String>(
        value: _filterPlatform,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        style: tt.labelSmall?.copyWith(color: cs.onSurface),
        icon: Icon(Icons.unfold_more_rounded, size: 14, color: cs.onSurfaceVariant),
        items: const {
          'all': 'All Platforms',
          'instagram': 'Instagram',
          'tiktok': 'TikTok',
          'other': 'Other'
        }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) setState(() { _filterPlatform = v; _modelsPage = 1; }); },
      ),
    );
  }

  Widget _modelTile(BuildContext context, Map<String, dynamic> mm, int index) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final imageUrl = mm['image'] as String?;
    final url = mm['url'] as String?;
    final yt = mm['yt'] as String?;
    final channel = (mm['channel'] ?? '').toString();
    final username = '${mm['username'] ?? mm['url'] ?? '—'}';
    final platform = '${mm['platform'] ?? 'other'}';
    final count = mm['count'] ?? 0;
    final hasThumb = imageUrl != null && imageUrl.isNotEmpty;

    // Rank badge for top 3
    Widget? rankBadge;
    if (index < 3 && _modelsPage == 1 && _modelSortBy == 'count' && !_modelSortAsc) {
      final colors = [AppTheme.accentAmber, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
      rankBadge = Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[index].withValues(alpha: 0.2),
          border: Border.all(color: colors[index], width: 1.5),
        ),
        child: Center(
          child: Text('#${index + 1}',
              style: tt.labelSmall?.copyWith(
                  color: colors[index], fontWeight: FontWeight.w800, fontSize: 9)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Column(
            children: [
              if (hasThumb)
                GestureDetector(
                  onTap: url != null && url.isNotEmpty ? () => _launch(url) : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 80,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 80, height: 50,
                        color: cs.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 80, height: 50,
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined, size: 16,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 80, height: 50,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_rounded, size: 20, color: cs.onSurfaceVariant),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${count}x',
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    )),
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (rankBadge != null) ...[rankBadge, const SizedBox(width: 6)],
                    Expanded(
                      child: url != null && url.isNotEmpty
                          ? InkWell(
                              onTap: () => _launch(url),
                              child: Text(username,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            )
                          : Text(username,
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (channel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(channel,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    PlatformBadge(platform: platform),
                    if (yt != null && yt.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _launch(yt),
                        child: Icon(Icons.play_circle_filled,
                            size: 16, color: AppTheme.accentRose),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection(BuildContext context, List<dynamic> audio) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totalPages = audio.isEmpty ? 1 : (audio.length / _audioPerPage).ceil();
    final page = _audioPage.clamp(1, totalPages);
    final start = (page - 1) * _audioPerPage;
    final end = (start + _audioPerPage).clamp(0, audio.length);
    final pageItems = audio.isEmpty ? <dynamic>[] : audio.sublist(start, end);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _audioCollapsed = !_audioCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _audioCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded,
                        size: 20, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Text('Music (most streamed)',
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('(${audio.length})',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          if (!_audioCollapsed) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            if (audio.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No audio stats yet',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              )
            else
              ...pageItems.map((a) {
                final aa = a as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${aa['name'] ?? '—'}',
                            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${aa['time_display'] ?? '—'}',
                              style: tt.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                          Text('${aa['chunks'] ?? 0} chunks · ${aa['seconds'] ?? 0}s',
                              style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            if (totalPages > 1)
              PaginationBar(
                page: page,
                totalPages: totalPages,
                onPrev: () => setState(() => _audioPage = page - 1),
                onNext: () => setState(() => _audioPage = page + 1),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
}
