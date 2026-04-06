import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact list tile for displaying a video chunk or audio file.
/// Used by both tabs in the library screen for a consistent layout.
class MediaListTile extends StatelessWidget {
  const MediaListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isNowPlaying = false,
    this.accentColor,
    this.onPlay,
    this.onDelete,
    this.onSources,
    this.badges = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isNowPlaying;
  /// Accent colour for the now-playing highlight (defaults to nowPlayingBlue).
  final Color? accentColor;
  final VoidCallback? onPlay;
  final VoidCallback? onDelete;
  final VoidCallback? onSources;
  /// Tiny trailing badges (e.g. codec, resolution).
  final List<BadgeInfo> badges;

  Color get _accent => accentColor ?? AppTheme.nowPlayingBlue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isNowPlaying
            ? _accent.withValues(alpha: 0.07)
            : Colors.transparent,
        border: isNowPlaying
            ? Border.all(color: _accent.withValues(alpha: 0.25))
            : null,
      ),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // ── Icon / thumbnail ──
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isNowPlaying ? _accent : cs.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isNowPlaying ? _accent : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),

              // ── Title / subtitle / now-playing label ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight:
                                  isNowPlaying ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNowPlaying) ...[
                          const SizedBox(width: 6),
                          _NowPlayingBadge(color: _accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Inline badges (codec, resolution)
                        for (final b in badges) ...[
                          const SizedBox(width: 6),
                          _TinyBadge(text: b.text, color: b.color),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Actions ──
              if (onSources != null)
                _ActionIcon(
                  icon: Icons.info_outline_rounded,
                  tooltip: 'Sources',
                  onTap: onSources!,
                ),
              if (onDelete != null && !isNowPlaying)
                _ActionIcon(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete',
                  onTap: onDelete!,
                  color: AppTheme.accentRose.withValues(alpha: 0.8),
                ),
              _ActionIcon(
                icon: isNowPlaying
                    ? Icons.skip_next_rounded
                    : Icons.play_arrow_rounded,
                tooltip: isNowPlaying ? 'Skip' : 'Play',
                onTap: onPlay ?? () {},
                color: isNowPlaying ? _accent : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ──

class BadgeInfo {
  const BadgeInfo({required this.text, required this.color});
  final String text;
  final Color color;
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            'NOW PLAYING',
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
