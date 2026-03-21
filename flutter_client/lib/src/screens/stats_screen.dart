import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/streaming_api.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/primary_meta_row.dart';

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
  int _modelsPage = 1;
  int _audioPage = 1;
  static const int _modelsPerPage = 20;
  static const int _audioPerPage = 12;
  /// ½ of the HTML reference size (140×84); was ¼, then doubled.
  static const double _modelThumbW = 140 / 2;
  static const double _modelThumbH = 84 / 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stats?['stream_stats'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final playCounts = _stats?['play_counts'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final models = playCounts['models'] as List<dynamic>? ?? <dynamic>[];
    final audio = playCounts['audio'] as List<dynamic>? ?? <dynamic>[];
    final modelsTotalPages = models.isEmpty ? 1 : (models.length / _modelsPerPage).ceil();
    final audioTotalPages = audio.isEmpty ? 1 : (audio.length / _audioPerPage).ceil();
    final modelsPage = _modelsPage.clamp(1, modelsTotalPages);
    final audioPage = _audioPage.clamp(1, audioTotalPages);
    final modelsStart = (modelsPage - 1) * _modelsPerPage;
    final audioStart = (audioPage - 1) * _audioPerPage;
    final modelsEnd = (modelsStart + _modelsPerPage).clamp(0, models.length);
    final audioEnd = (audioStart + _audioPerPage).clamp(0, audio.length);
    final modelsPageItems = models.isEmpty ? <dynamic>[] : models.sublist(modelsStart, modelsEnd);
    final audioPageItems = audio.isEmpty ? <dynamic>[] : audio.sublist(audioStart, audioEnd);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SelectionArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                DashboardHeader(
                  title: 'Stats',
                  onRefresh: _loading ? null : _load,
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stream Stats', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _kv('Time played', '${stream['time_played'] ?? '-'}'),
                        _kv('Chunks pushed', '${stream['chunks_pushed'] ?? '-'}'),
                        _kv('Chunks created', '${stream['chunks_created_total'] ?? '-'}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top Models (${models.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (models.isEmpty)
                          const Text('No model stats yet')
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              const gap = 12.0;
                              final leftCol = <Widget>[];
                              final rightCol = <Widget>[];
                              for (var i = 0; i < modelsPageItems.length; i++) {
                                final mm = modelsPageItems[i] as Map<String, dynamic>;
                                final tile = Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _modelTile(context, mm),
                                );
                                if (i < 10) {
                                  leftCol.add(tile);
                                } else {
                                  rightCol.add(tile);
                                }
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: leftCol,
                                    ),
                                  ),
                                  SizedBox(width: gap),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: rightCol,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        if (models.isNotEmpty)
                          _pager(
                            page: modelsPage,
                            totalPages: modelsTotalPages,
                            onPrev: modelsPage > 1
                                ? () => setState(() => _modelsPage = modelsPage - 1)
                                : null,
                            onNext: modelsPage < modelsTotalPages
                                ? () => setState(() => _modelsPage = modelsPage + 1)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top Audio (${audio.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (audio.isEmpty)
                          const Text('No audio stats yet')
                        else
                          ...audioPageItems.map((a) {
                            final aa = a as Map<String, dynamic>;
                            final cs = Theme.of(context).colorScheme;
                            final tt = Theme.of(context).textTheme;
                            return PrimaryMetaRow(
                              primary: '${aa['name'] ?? '-'}',
                              meta:
                                  '${aa['seconds'] ?? 0}s • ${aa['chunks'] ?? 0} chunks',
                              trailing: Text(
                                '${aa['time_display'] ?? '-'}',
                                style: tt.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            );
                          }),
                        if (audio.isNotEmpty)
                          _pager(
                            page: audioPage,
                            totalPages: audioTotalPages,
                            onPrev: audioPage > 1
                                ? () => setState(() => _audioPage = audioPage - 1)
                                : null,
                            onNext: audioPage < audioTotalPages
                                ? () => setState(() => _audioPage = audioPage + 1)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
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
    final username = '${mm['username'] ?? mm['url'] ?? '-'}';
    final platform = '${mm['platform'] ?? 'other'}';
    final count = mm['count'] ?? 0;
    final hasThumb = imageUrl != null && imageUrl.isNotEmpty;

    Widget imageBlock = const SizedBox.shrink();
    if (hasThumb) {
      imageBlock = Container(
        width: _modelThumbW,
        height: _modelThumbH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cs.outline.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => ColoredBox(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 22),
          ),
        ),
      );
      if (url != null && url.isNotEmpty) {
        imageBlock = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _launchUrl(url),
            child: imageBlock,
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasThumb) ...[
          imageBlock,
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (channel.isNotEmpty) ...[
                Text(
                  channel,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
              ],
              if (url != null && url.isNotEmpty)
                InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    username,
                    style: channel.isNotEmpty
                        ? tt.bodyMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : tt.titleSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Text(
                  username,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 2),
              Text(
                platform,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (yt != null && yt.isNotEmpty) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchUrl(yt),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_filled, size: 14, color: cs.error),
                      const SizedBox(width: 4),
                      Text(
                        'YouTube',
                        style: tt.labelSmall?.copyWith(color: cs.error, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${count}x',
          style: tt.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Widget _kv(String k, String v) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager({
    required int page,
    required int totalPages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          OutlinedButton(onPressed: onPrev, child: const Text('Prev')),
          const SizedBox(width: 10),
          Text('Page $page of $totalPages'),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}
