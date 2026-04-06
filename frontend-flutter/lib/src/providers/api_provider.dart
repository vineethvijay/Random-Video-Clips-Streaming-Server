import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../services/streaming_api.dart';

/// Single source of truth for the API client.
final apiProvider = Provider<StreamingApi>((ref) {
  return StreamingApi(config: AppConfig.fromEnvironment());
});
