import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Persistent mini player bar showing current chunk + audio with skip controls.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    this.currentChunk,
    this.currentAudio,
    this.chunkProgress = 0,
    this.onSkipVideo,
    this.onSkipAudio,
  });

  final String? currentChunk;
  final String? currentAudio;
  final double chunkProgress;
  final VoidCallback? onSkipVideo;
  final VoidCallback? onSkipAudio;

  @override
  Widget build(BuildContext context) {
    if (currentChunk == null && currentAudio == null) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLow,
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thin progress bar
          ClipRRect(
            child: LinearProgressIndicator(
              value: chunkProgress.clamp(0.0, 1.0),
              backgroundColor: Colors.transparent,
              color: AppTheme.nowPlayingBlue,
              minHeight: 2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Video info
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.nowPlayingBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.live_tv_rounded,
                      size: 18, color: AppTheme.nowPlayingBlue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentChunk ?? 'No video',
                        style: tt.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (currentAudio != null)
                        Text(
                          currentAudio!,
                          style: tt.labelSmall?.copyWith(
                            color: AppTheme.accentEmerald,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Skip audio
                IconButton(
                  onPressed: onSkipAudio,
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  tooltip: 'Skip Audio',
                  color: AppTheme.accentEmerald,
                  visualDensity: VisualDensity.compact,
                ),
                // Skip video
                IconButton(
                  onPressed: onSkipVideo,
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                  tooltip: 'Skip Video',
                  color: AppTheme.nowPlayingBlue,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
