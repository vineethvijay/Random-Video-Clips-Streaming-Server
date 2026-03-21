import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/streaming_api.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.api});
  final StreamingApi api;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  // Models state
  bool _modelsCollapsed = false;
  String _modelSearch = '';
  String _modelSortBy = 'count';
  bool _modelSortAsc = false;
  String _filterPlatform = 'all';
  String _filterThumb = 'all';
  int _modelsPage = 1;
  static const int _modelsPerPage = 20;

  // Audio state
  bool _audioCollapsed = true;
  int _audioPage = 1;
  static const int _audioPerPage = 12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.getStats();
      if (!mounted) return;
      setState(() {
        _stats = data;
        _modelsPage = 1;
        _audioPage = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  // ── Computed model list ──

  List<Map<String, dynamic>> get _allModels {
    final pc = _stats?['play_counts'] as Map<String, dynamic>? ?? {};
    final raw = pc['models'] as List<dynamic>? ?? [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> get _filteredModels {
    var out = _allModels.toList();
    // Platform filter
    if (_filterPlatform != 'all') {
      out = out.where((m) => m['platform'] == _filterPlatform).toList();
    }
    // Thumbnail filter
    if (_filterThumb == 'yes') {
      out = out.where((m) {
        final img = m['image'];
        return img != null && img.toString().isNotEmpty;
      }).toList();
    } else if (_filterThumb == 'no') {
      out = out.where((m) {
        final img = m['image'];
        return img == null || img.toString().isEmpty;
      }).toList();
    }
    // Search
    if (_modelSearch.isNotEmpty) {
      final q = _modelSearch.toLowerCase();
      out = out.where((m) {
        final u = (m['username'] ?? '').toString().toLowerCase();
        final c = (m['channel'] ?? '').toString().toLowerCase();
        return u.contains(q) || c.contains(q);
      }).toList();
    }
    // Sort
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
        case 'platform':
          va = (a['platform'] ?? '').toString();
          vb = (b['platform'] ?? '').toString();
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
    final stream = _stats?['stream_stats'] as Map<String, dynamic>? ?? {};
    final playCountsAudio = (_stats?['play_counts'] as Map<String, dynamic>?)?['audio'] as List<dynamic>? ?? [];

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildStreamStats(context, stream),
                    const SizedBox(height: 16),
                    _buildModelsSection(context),
                    const SizedBox(height: 16),
                    _buildAudioSection(context, playCountsAudio),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          child: Icon(Icons.bar_chart_rounded, color: cs.primary, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stats',
                  style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              Text('Play counts & stream data',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ── Stream stats ──

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
    );
  }

  // ── Models section ──

  Widget _buildModelsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final models = _filteredModels;
    final totalPages = models.isEmpty ? 1 : (models.length / _modelsPerPage).ceil();
    final page = _modelsPage.clamp(1, totalPages);
    final start = (page - 1) * _modelsPerPage;
    final end = (start + _modelsPerPage).clamp(0, models.length);
    final pageModels = models.isEmpty ? <Map<String, dynamic>>[] : models.sublist(start, end);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Collapsible header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _modelsCollapsed = !_modelsCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _modelsCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    size: 20, color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('Models', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(
                    '(${models.length}${models.length != _allModels.length ? '/${_allModels.length}' : ''})',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (!_modelsCollapsed) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ..._sortBtn(context, 'Plays', 'count'),
                  ..._sortBtn(context, 'Name', 'username'),
                  ..._sortBtn(context, 'Channel', 'channel'),
                  ..._sortBtn(context, 'Platform', 'platform'),
                  const SizedBox(width: 4),
                  _dropdownFilter<String>(
                    context: context,
                    value: _filterPlatform,
                    items: const {'all': 'All platforms', 'instagram': 'Instagram', 'tiktok': 'TikTok', 'other': 'Other'},
                    onChanged: (v) => setState(() { _filterPlatform = v; _modelsPage = 1; }),
                  ),
                  _dropdownFilter<String>(
                    context: context,
                    value: _filterThumb,
                    items: const {'all': 'All thumbnails', 'yes': 'Has thumbnail', 'no': 'No thumbnail'},
                    onChanged: (v) => setState(() { _filterThumb = v; _modelsPage = 1; }),
                  ),
                  SizedBox(
                    width: 140,
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
            // Grid
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No model stats yet',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 500;
                    if (!isWide) {
                      return Column(
                        children: pageModels.map((m) => _modelTile(context, m)).toList(),
                      );
                    }
                    final left = <Widget>[];
                    final right = <Widget>[];
                    for (var i = 0; i < pageModels.length; i++) {
                      (i % 2 == 0 ? left : right).add(_modelTile(context, pageModels[i]));
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: left)),
                          VerticalDivider(
                            width: 24,
                            thickness: 1,
                            color: cs.outline.withValues(alpha: 0.2),
                          ),
                          Expanded(child: Column(children: right)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            // Pagination
            if (totalPages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Page $page of $totalPages',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    Row(children: [
                      IconButton(
                        onPressed: page > 1 ? () => setState(() => _modelsPage = page - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: page < totalPages ? () => setState(() => _modelsPage = page + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  List<Widget> _sortBtn(BuildContext context, String label, String field) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final active = _modelSortBy == field;
    final arrow = active ? (_modelSortAsc ? ' ↑' : ' ↓') : '';
    return [
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _setModelSort(field),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active ? cs.primary : cs.surfaceContainerHighest,
          ),
          child: Text('$label$arrow',
              style: tt.labelSmall?.copyWith(
                color: active ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
        ),
      ),
    ];
  }

  Widget _dropdownFilter<T>({
    required BuildContext context,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        style: tt.labelSmall?.copyWith(color: cs.onSurface),
        icon: Icon(Icons.unfold_more_rounded, size: 14, color: cs.onSurfaceVariant),
        items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }

  Widget _modelTile(BuildContext context, Map<String, dynamic> mm) {
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

    // Determine platform icon
    IconData platformIcon = Icons.link_rounded;
    Color platformColor = cs.onSurfaceVariant;
    if (platform == 'instagram') {
      platformIcon = Icons.camera_alt_rounded;
      platformColor = AppTheme.accentRose;
    } else if (platform == 'tiktok') {
      platformIcon = Icons.music_video_rounded;
      platformColor = AppTheme.accentCyan;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image + play count badge
          Column(
            children: [
              if (hasThumb)
                GestureDetector(
                  onTap: url != null && url.isNotEmpty ? () => _launch(url) : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      width: 100,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100, height: 60,
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined, size: 18, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 100, height: 60,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_rounded, size: 24, color: cs.onSurfaceVariant),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${count}x played',
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
                // Username / model name — bigger, on top
                if (url != null && url.isNotEmpty)
                  InkWell(
                    onTap: () => _launch(url),
                    child: Text(username,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          fontSize: 14,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                else
                  Text(username,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                // Channel below
                if (channel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(channel,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 6),
                // Social icons row — icon only, no text
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (url != null && url.isNotEmpty)
                      IconButton(
                        onPressed: () => _launch(url),
                        icon: Icon(platformIcon, size: 18, color: platformColor),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: platform,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (yt != null && yt.isNotEmpty)
                      IconButton(
                        onPressed: () => _launch(yt),
                        icon: Icon(Icons.play_circle_filled, size: 18, color: AppTheme.accentRose),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: 'YouTube',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio section ──

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
                  Icon(
                    _audioCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    size: 20, color: cs.onSurfaceVariant,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Page $page of $totalPages',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    Row(children: [
                      IconButton(
                        onPressed: page > 1 ? () => setState(() => _audioPage = page - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: page < totalPages ? () => setState(() => _audioPage = page + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
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
