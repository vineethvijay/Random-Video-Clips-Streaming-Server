class StreamStatus {
  StreamStatus({
    this.currentChunk,
    this.currentAudio,
    this.chunksPushed = 0,
    this.chunksCreatedTotal = 0,
    this.totalSecondsStreamed = 0,
  });

  final String? currentChunk;
  final String? currentAudio;
  final int chunksPushed;
  final int chunksCreatedTotal;
  final num totalSecondsStreamed;

  factory StreamStatus.fromJson(Map<String, dynamic> json) {
    return StreamStatus(
      currentChunk: json['current_chunk'] as String?,
      currentAudio: json['current_audio'] as String?,
      chunksPushed: json['chunks_pushed'] as int? ?? 0,
      chunksCreatedTotal: json['chunks_created_total'] as int? ?? 0,
      totalSecondsStreamed: json['total_seconds_streamed'] as num? ?? 0,
    );
  }
}
