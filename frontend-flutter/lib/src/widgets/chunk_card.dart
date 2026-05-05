import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/chunk.dart';
import '../theme/app_theme.dart';

/// Rich card for displaying a video chunk with thumbnail, metadata badges, and actions.
class ChunkCard extends StatelessWidget {
  const ChunkCard({
    super.key,
    required this.chunk,
    this.isNowPlaying = false,
    this.progress,
    this.elapsedLabel,
    this.totalLabel,
    this.onPlay,
    this.onSources,
  });

  final Chunk chunk;
  final bool isNowPlaying;
  final double? progress;
  final String? elapsedLabel;
  final String? totalLabel;
  final VoidCallback? onPlay;
  final VoidCallback? onSources;

  String get _thumbnailUrl {
    if (chunk.sourceVideos != null && chunk.sourceVideos!.isNotEmpty) {
      final first = chunk.sourceVideos!.first;
      final thumb = first['thumbnail_url'] as String?;
      if (thumb != null && thumb.isNotEmpty) return thumb;
    }
    return '';
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
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isNowPlaying
            ? AppTheme.nowPlayingBlue.withValues(alpha: 0.08)
            : cs.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(
          color: isNowPlaying
              ? AppTheme.nowPlayingBlue.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(13)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumbnailUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: _thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: Icon(Icons.movie_rounded,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                              size: 32),
                        ),
                      ),
                      errorWidget: (_, __, ___) =>
                          _GradientPlaceholder(name: chunk.name),
                    )
                  else
                    _GradientPlaceholder(name: chunk.name),
                  // Now playing overlay
                  if (isNowPlaying)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.nowPlayingBlue.withValues(alpha: 0.9),
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
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('NOW PLAYING',
                                style: tt.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                  // Badges
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (chunk.videoCodec != null)
                          _Badge(
                              text: chunk.videoCodec!.toUpperCase(),
                              color: AppTheme.accentCyan),
                        if (chunk.width != null && chunk.height != null) ...[
                          const SizedBox(width: 4),
                          _Badge(
                              text: '${chunk.width}x${chunk.height}',
                              color: AppTheme.accentLavender),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chunk.name,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _relativeTime(chunk.createdAt),
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${chunk.sizeMb} MB',
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (chunk.daysToExpire != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${chunk.daysToExpire}d left',
                        style: tt.labelSmall?.copyWith(
                          color: chunk.daysToExpire! <= 2
                              ? AppTheme.accentRose
                              : cs.onSurfaceVariant,
                          fontWeight: chunk.daysToExpire! <= 2
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
                // Progress bar for now playing
                if (isNowPlaying && progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      backgroundColor:
                          cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      color: AppTheme.nowPlayingBlue,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        elapsedLabel ?? '0:00',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        totalLabel ?? '0:00',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton.tonalIcon(
                          onPressed: onPlay,
                          icon: Icon(
                              isNowPlaying
                                  ? Icons.skip_next_rounded
                                  : Icons.play_arrow_rounded,
                              size: 16),
                          label: Text(isNowPlaying ? 'Skip' : 'Play',
                              style: const TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                    if (chunk.hasSources) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: onSources,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Sources',
                              style: TextStyle(fontSize: 12)),
                        ),
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
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
      ),
    );
  }
}

/// Gradient placeholder when no thumbnail available.
class _GradientPlaceholder extends StatelessWidget {
  const _GradientPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final hash = name.hashCode;
    final colors = [
      [AppTheme.seed, AppTheme.accentCyan],
      [AppTheme.accentRose, AppTheme.accentAmber],
      [AppTheme.accentEmerald, AppTheme.accentCyan],
      [AppTheme.accentLavender, AppTheme.accentRose],
      [AppTheme.nowPlayingBlue, AppTheme.seed],
    ];
    final pair = colors[hash.abs() % colors.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            pair[0].withValues(alpha: 0.4),
            pair[1].withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          color: Colors.white.withValues(alpha: 0.3),
          size: 36,
        ),
      ),
    );
  }
}
