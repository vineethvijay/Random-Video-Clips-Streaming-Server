class Chunk {
  Chunk({
    required this.name,
    required this.createdAt,
    required this.sizeMb,
    this.daysToExpire,
    this.videoCodec,
    this.width,
    this.height,
    this.timestamp,
    this.sourceVideos,
  });

  final String name;
  final String createdAt;
  final num sizeMb;
  final int? daysToExpire;
  final String? videoCodec;
  final int? width;
  final int? height;
  final num? timestamp;
  final List<Map<String, dynamic>>? sourceVideos;

  factory Chunk.fromJson(Map<String, dynamic> json) {
    final rawSources = json['source_videos'];
    List<Map<String, dynamic>>? sources;
    if (rawSources is List) {
      sources = rawSources
          .map((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is String) return <String, dynamic>{'path': e};
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    return Chunk(
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      sizeMb: (json['size_mb'] as num?) ?? 0,
      daysToExpire: json['days_to_expire'] as int?,
      videoCodec: json['video_codec'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      timestamp: json['timestamp'] as num?,
      sourceVideos: sources,
    );
  }

  bool get hasSources =>
      sourceVideos != null && sourceVideos!.isNotEmpty;

  String get metaSummary {
    final parts = <String>[];
    if (videoCodec != null) {
      var v = 'Video: $videoCodec';
      if (width != null && height != null) v += ' ${width}x$height';
      parts.add(v);
    }
    parts.add('Size: $sizeMb MB');
    parts.add('Created: $createdAt');
    if (daysToExpire != null) parts.add('Expires: ~${daysToExpire}d');
    return parts.join(' · ');
  }
}
