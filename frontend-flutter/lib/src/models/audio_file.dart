class AudioFile {
  AudioFile({
    required this.name,
    required this.path,
    required this.relPath,
    required this.sizeMb,
    this.durationSec,
    this.durationDisplay,
  });

  final String name;
  final String path;
  final String relPath;
  final num sizeMb;
  final num? durationSec;
  final String? durationDisplay;

  factory AudioFile.fromJson(Map<String, dynamic> json) {
    return AudioFile(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      relPath: json['rel_path'] as String? ?? '',
      sizeMb: (json['size_mb'] as num?) ?? 0,
      durationSec: json['duration_sec'] as num?,
      durationDisplay: json['duration_display'] as String?,
    );
  }
}
