class Chunk {
  Chunk({
    required this.name,
    required this.createdAt,
    required this.sizeMb,
    this.daysToExpire,
  });

  final String name;
  final String createdAt;
  final num sizeMb;
  final int? daysToExpire;

  factory Chunk.fromJson(Map<String, dynamic> json) {
    return Chunk(
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      sizeMb: (json['size_mb'] as num?) ?? 0,
      daysToExpire: json['days_to_expire'] as int?,
    );
  }
}
