import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:random_video_streamer_client/main.dart';

void main() {
  testWidgets('app builds with theme', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RandomVideoStreamerApp()),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
