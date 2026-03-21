import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chunk.dart';
import '../theme/app_theme.dart';

/// Bottom sheet that displays source videos for a chunk.
class SourcesSheet extends StatelessWidget {
  const SourcesSheet({
    super.key,
    required this.chunkName,
    required this.sources,
  });

  final String chunkName;
  final List<Map<String, dynamic>> sources;

  static void show(BuildContext context, Chunk chunk) {
    if (!chunk.hasSources) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourcesSheet(
        chunkName: chunk.name,
        sources: chunk.sourceVideos!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
                color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sources: $chunkName',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  itemCount: sources.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _SourceTile(source: sources[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final Map<String, dynamic> source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final path = source['path'] as String? ?? '';
    final model = source['model'] as String?;
    final thumbUrl = source['thumbnail_url'] as String?;
    final rawChannel = source['channel'];
    final title = source['title'] as String?;

    String channel = '';
    if (rawChannel is Map) {
      channel = (rawChannel['channel_name'] ??
              rawChannel['channel'] ??
              '')
          .toString();
    } else if (rawChannel is String) {
      channel = rawChannel;
    }

    final stem = path.split('/').last.replaceAll(
        RegExp(r'\.(mp4|mkv|avi)$', caseSensitive: false), '');
    final isYtId = stem.length == 11 &&
        RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(stem);
    final ytUrl = isYtId
        ? 'https://www.youtube.com/watch?v=$stem'
        : null;

    final thumbSrc = isYtId
        ? 'https://img.youtube.com/vi/$stem/hqdefault.jpg'
        : thumbUrl;

    final displayName =
        channel.isNotEmpty ? channel : (title ?? stem);
    final parsedModel = model != null ? _parseModel(model) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbSrc != null && thumbSrc.isNotEmpty)
          GestureDetector(
            onTap: ytUrl != null ? () => _launch(ytUrl) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                thumbSrc,
                width: 120,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 120,
                  height: 70,
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.broken_image_outlined,
                      color: cs.onSurfaceVariant, size: 20),
                ),
              ),
            ),
          ),
        if (thumbSrc != null && thumbSrc.isNotEmpty)
          const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (parsedModel != null) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: parsedModel.href != null
                      ? () => _launch(parsedModel.href!)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (parsedModel.icon != null)
                        Icon(parsedModel.icon,
                            size: 14, color: AppTheme.accentCyan),
                      if (parsedModel.icon != null)
                        const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          parsedModel.name,
                          style: tt.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (ytUrl != null) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launch(ytUrl),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_filled,
                          size: 14, color: AppTheme.accentRose),
                      const SizedBox(width: 4),
                      Text(
                        'YouTube',
                        style: tt.labelSmall?.copyWith(
                          color: AppTheme.accentRose,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  _ParsedModel? _parseModel(String modelStr) {
    final m = modelStr
        .trim()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'^www\.'), '');
    final href = modelStr.startsWith('http')
        ? modelStr
        : 'https://$m';

    if (RegExp(r'instagram\.com/', caseSensitive: false).hasMatch(m)) {
      final name = m
          .replaceAll(
              RegExp(r'.*instagram\.com/@?', caseSensitive: false), '')
          .split(RegExp(r'[/\?#]'))
          .first;
      return _ParsedModel(
          icon: Icons.camera_alt_outlined,
          name: name.isNotEmpty ? name : m,
          href: href);
    }
    if (RegExp(r'tiktok\.com', caseSensitive: false).hasMatch(m)) {
      final match = RegExp(r'@([a-zA-Z0-9_.]+)').firstMatch(m);
      final name = match != null
          ? '@${match.group(1)}'
          : m.split(RegExp(r'[/\?#]')).last;
      return _ParsedModel(
          icon: Icons.music_video_outlined,
          name: name.isNotEmpty ? name : m,
          href: href);
    }
    return _ParsedModel(
        icon: Icons.link_rounded,
        name: m.length > 36 ? '${m.substring(0, 33)}…' : m,
        href: href);
  }
}

class _ParsedModel {
  _ParsedModel({this.icon, required this.name, this.href});
  final IconData? icon;
  final String name;
  final String? href;
}
