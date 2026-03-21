import '../config/app_config.dart';
import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../models/system_usage.dart';
import 'api_client.dart';

class StreamingApi {
  StreamingApi({
    required this.config,
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient(baseUrl: config.apiBaseUrl);

  final AppConfig config;
  final ApiClient _apiClient;

  factory StreamingApi.fromEnvironment() {
    return StreamingApi(config: AppConfig.fromEnvironment());
  }

  Future<StreamStatus> getStreamStatus() async {
    final json = await _apiClient.getJson('/api/stream-status');
    return StreamStatus.fromJson(json);
  }

  Future<SystemUsage> getSystemUsage() async {
    final json = await _apiClient.getJson('/api/system-usage');
    return SystemUsage.fromJson(json);
  }

  Future<List<Chunk>> getChunks({int offset = 0, int limit = 20}) async {
    final json = await _apiClient.getJson(
      '/api/chunks',
      query: {'offset': offset, 'limit': limit},
    );
    final list = (json['chunks'] as List<dynamic>? ?? <dynamic>[]);
    return list
        .whereType<Map<String, dynamic>>()
        .map(Chunk.fromJson)
        .toList(growable: false);
  }

  Future<List<AudioFile>> getAudioFiles({int offset = 0, int limit = 100}) async {
    final json = await _apiClient.getJson(
      '/api/audio',
      query: {'offset': offset, 'limit': limit},
    );
    final list = (json['audio_files'] as List<dynamic>? ?? <dynamic>[]);
    return list
        .whereType<Map<String, dynamic>>()
        .map(AudioFile.fromJson)
        .toList(growable: false);
  }

  Future<ServerStatus> getServerStatus() async {
    final json = await _apiClient.getJson('/api/status');
    return ServerStatus.fromJson(json);
  }

  Future<Map<String, dynamic>> getAdminContext() async {
    return _apiClient.getJson('/api/admin-context');
  }

  Future<Map<String, dynamic>> getStats() async {
    return _apiClient.getJson('/api/stats');
  }

  Future<Map<String, dynamic>> getCronHistory({int page = 1, int perPage = 20}) async {
    return _apiClient.getJson(
      '/api/cron-run-history',
      query: {'page': page, 'per_page': perPage},
    );
  }

  Future<Map<String, dynamic>> getCron() async {
    return _apiClient.getJson('/api/cron');
  }

  Future<void> setCron(String schedule) async {
    await _apiClient.postJson('/api/cron', body: {'schedule': schedule});
  }

  Future<void> removeCron() async {
    await _apiClient.deleteJson('/api/cron');
  }

  Future<void> skipToNext() async {
    await _apiClient.postJson('/api/skip_to_next');
  }

  Future<void> skipToNextAudio() async {
    await _apiClient.postJson('/api/skip_to_next_audio');
  }

  Future<void> generateChunks() async {
    await _apiClient.postJson('/api/generate_chunk');
  }

  Future<void> playChunk(String chunkName) async {
    await _apiClient.postJson('/api/play_chunk', body: {'chunk_name': chunkName});
  }

  Future<void> playAudio(String audioName) async {
    await _apiClient.postJson('/api/play_audio', body: {'audio_name': audioName});
  }

  Future<void> deleteAudio(String path) async {
    await _apiClient.postJson('/api/delete_audio', body: {'path': path});
  }

  Future<void> updateSettings(Map<String, dynamic> payload) async {
    await _apiClient.postJson('/api/update_settings', body: payload);
  }

  Future<void> restartChunkGenerator() async {
    await _apiClient.postJson('/api/restart_chunk_generator');
  }

  Future<void> stopGeneration() async {
    await _apiClient.postJson('/api/stop_generation');
  }
}
