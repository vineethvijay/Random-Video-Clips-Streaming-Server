import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Platform badge for Instagram/TikTok/YouTube/Other.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, required this.platform});

  final String platform;

  static const _config = <String, (IconData, Color, String)>{
    'instagram': (Icons.camera_alt_rounded, AppTheme.accentRose, 'IG'),
    'tiktok': (Icons.music_video_rounded, AppTheme.accentCyan, 'TT'),
    'youtube': (Icons.play_circle_filled, AppTheme.accentRose, 'YT'),
  };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (icon, color, label) =
        _config[platform.toLowerCase()] ??
        (Icons.link_rounded, Theme.of(context).colorScheme.onSurfaceVariant, platform.substring(0, 2).toUpperCase());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: tt.labelSmall?.copyWith(
                  color: color, fontWeight: FontWeight.w700, fontSize: 9)),
        ],
      ),
    );
  }
}
