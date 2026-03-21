class StreamStatus {
  StreamStatus({
    this.currentChunk,
    this.currentAudio,
    this.chunksPushed = 0,
    this.chunksCreatedTotal = 0,
    this.totalSecondsStreamed = 0,
    this.currentChunkStartedAt,
    this.currentChunkDuration,
    this.audioPositionSec,
    this.audioTrackDurationSec,
  });

  final String? currentChunk;
  final String? currentAudio;
  final int chunksPushed;
  final int chunksCreatedTotal;
  final num totalSecondsStreamed;
  final num? currentChunkStartedAt;
  final num? currentChunkDuration;
  final num? audioPositionSec;
  final num? audioTrackDurationSec;

  factory StreamStatus.fromJson(Map<String, dynamic> json) {
    return StreamStatus(
      currentChunk: json['current_chunk'] as String?,
      currentAudio: json['current_audio'] as String?,
      chunksPushed: json['chunks_pushed'] as int? ?? 0,
      chunksCreatedTotal: json['chunks_created_total'] as int? ?? 0,
      totalSecondsStreamed: json['total_seconds_streamed'] as num? ?? 0,
      currentChunkStartedAt: json['current_chunk_started_at'] as num?,
      currentChunkDuration: json['current_chunk_duration'] as num?,
      audioPositionSec: json['audio_position_sec'] as num?,
      audioTrackDurationSec: json['audio_track_duration_sec'] as num?,
    );
  }
}
