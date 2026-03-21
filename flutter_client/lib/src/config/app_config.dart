import 'package:flutter/foundation.dart' show kIsWeb;

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

  /// On web, if URLs were built with `localhost` / `127.0.0.1`, rewrite the
  /// host to match [Uri.base] (the page you opened, e.g. `http://192.168.0.11:8090/`).
  /// Otherwise the browser talks to the viewer's machine, not the server — HLS spins forever.
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
      apiBaseUrl: _sameHostAsPageWhenLocalhost(apiBaseUrl),
      hlsUrl: _sameHostAsPageWhenLocalhost(hlsUrl),
      enableLiveStream: enableLiveStream,
      refreshSeconds: refreshSeconds,
    );
  }

  static String _sameHostAsPageWhenLocalhost(String url) {
    if (!kIsWeb) {
      return url;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return url;
    }
    final page = Uri.base;
    if (page.host.isEmpty) {
      return url;
    }
    final h = parsed.host;
    if (h != 'localhost' && h != '127.0.0.1') {
      return url;
    }
    final next = parsed.replace(host: page.host, scheme: page.scheme);
    return next.toString();
  }
}
