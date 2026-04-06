import 'package:flutter/material.dart';

import '../models/audio_file.dart';
import '../theme/app_theme.dart';

/// Rich card for displaying an audio file.
class AudioCard extends StatelessWidget {
  const AudioCard({
    super.key,
    required this.audio,
    this.isNowPlaying = false,
    this.progress,
    this.elapsedLabel,
    this.totalLabel,
    this.onPlay,
    this.onDelete,
  });

  final AudioFile audio;
  final bool isNowPlaying;
  final double? progress;
  final String? elapsedLabel;
  final String? totalLabel;
  final VoidCallback? onPlay;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isNowPlaying
            ? AppTheme.accentEmerald.withValues(alpha: 0.08)
            : cs.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(
          color: isNowPlaying
              ? AppTheme.accentEmerald.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isNowPlaying
                            ? AppTheme.accentEmerald
                            : cs.primary)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isNowPlaying
                        ? Icons.music_note_rounded
                        : Icons.audiotrack_rounded,
                    size: 20,
                    color:
                        isNowPlaying ? AppTheme.accentEmerald : cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              audio.name,
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNowPlaying)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentEmerald
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('PLAYING',
                                  style: tt.labelSmall?.copyWith(
                                      color: AppTheme.accentEmerald,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${audio.sizeMb} MB${audio.durationDisplay != null ? '  ·  ${audio.durationDisplay}' : ''}',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Progress bar for now playing
            if (isNowPlaying && progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  backgroundColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  color: AppTheme.accentEmerald,
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
                if (onDelete != null && !isNowPlaying) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 32,
                    width: 32,
                    child: IconButton(
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 16,
                          color: AppTheme.accentRose.withValues(alpha: 0.8)),
                      padding: EdgeInsets.zero,
                      tooltip: 'Delete',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
