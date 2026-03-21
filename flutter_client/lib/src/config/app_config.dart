class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.hlsUrl,
    this.enableLiveStream = false,
    this.refreshSeconds = 5,
  });

  final String apiBaseUrl;
  final String hlsUrl;
  final bool enableLiveStream;
  final int refreshSeconds;

  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8081',
    );
    const hlsUrl = String.fromEnvironment(
      'HLS_URL',
      defaultValue: 'http://localhost:8082/hls/stream.m3u8',
    );
    const enableLiveStream = bool.fromEnvironment(
      'ENABLE_LIVE_STREAM',
      defaultValue: false,
    );
    const refreshSeconds = int.fromEnvironment('REFRESH_SECONDS', defaultValue: 5);
    return AppConfig(
      apiBaseUrl: apiBaseUrl,
      hlsUrl: hlsUrl,
      enableLiveStream: enableLiveStream,
      refreshSeconds: refreshSeconds,
    );
  }
}
