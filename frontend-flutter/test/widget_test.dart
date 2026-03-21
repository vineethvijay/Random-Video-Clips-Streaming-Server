import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:random_video_streamer_client/main.dart';
import 'package:random_video_streamer_client/src/config/app_config.dart';
import 'package:random_video_streamer_client/src/services/streaming_api.dart';

void main() {
  testWidgets('app builds with theme', (WidgetTester tester) async {
    final api = StreamingApi(
      config: AppConfig(
        apiBaseUrl: 'http://127.0.0.1:9',
        hlsUrl: 'http://127.0.0.1:9',
        enableLiveStream: false,
        refreshSeconds: 9999,
      ),
    );
    await tester.pumpWidget(RandomVideoStreamerApp(api: api));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
