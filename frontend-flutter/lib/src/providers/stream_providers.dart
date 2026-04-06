import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_file.dart';
import '../models/chunk.dart';
import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../models/system_usage.dart';
import '../services/streaming_api.dart';
import 'api_provider.dart';

// ── Stream status (5s polling) ──

final streamStatusProvider =
    StateNotifierProvider<_StreamStatusNotifier, AsyncValue<StreamStatus>>(
        (ref) {
  final api = ref.watch(apiProvider);
  return _StreamStatusNotifier(api, ref);
});

class _StreamStatusNotifier extends StateNotifier<AsyncValue<StreamStatus>> {
  _StreamStatusNotifier(this._api, this._ref)
      : super(const AsyncValue.loading()) {
    _fetch();
    _timer = Timer.periodic(
      Duration(seconds: _ref.read(apiProvider).config.refreshSeconds),
      (_) => _fetch(),
    );
  }

  final StreamingApi _api;
  final Ref _ref;
  Timer? _timer;

  Future<void> _fetch() async {
    try {
      final status = await _api.getStreamStatus();
      if (mounted) state = AsyncValue.data(status);
    } catch (e, st) {
      if (mounted && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Server status (5s polling) ──

final serverStatusProvider =
    StateNotifierProvider<_ServerStatusNotifier, AsyncValue<ServerStatus>>(
        (ref) {
  final api = ref.watch(apiProvider);
  return _ServerStatusNotifier(api, ref);
});

class _ServerStatusNotifier extends StateNotifier<AsyncValue<ServerStatus>> {
  _ServerStatusNotifier(this._api, this._ref)
      : super(const AsyncValue.loading()) {
    _fetch();
    _timer = Timer.periodic(
      Duration(seconds: _ref.read(apiProvider).config.refreshSeconds),
      (_) => _fetch(),
    );
  }

  final StreamingApi _api;
  final Ref _ref;
  Timer? _timer;

  Future<void> _fetch() async {
    try {
      final status = await _api.getServerStatus();
      if (mounted) state = AsyncValue.data(status);
    } catch (e, st) {
      if (mounted && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── System usage (10s polling) ──

final systemUsageProvider =
    StateNotifierProvider<_SystemUsageNotifier, AsyncValue<SystemUsage>>((ref) {
  final api = ref.watch(apiProvider);
  return _SystemUsageNotifier(api);
});

class _SystemUsageNotifier extends StateNotifier<AsyncValue<SystemUsage>> {
  _SystemUsageNotifier(this._api) : super(const AsyncValue.loading()) {
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
  }

  final StreamingApi _api;
  Timer? _timer;

  Future<void> _fetch() async {
    try {
      final usage = await _api.getSystemUsage();
      if (mounted) state = AsyncValue.data(usage);
    } catch (e, st) {
      if (mounted && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Chunks (5s polling) ──

final chunksProvider =
    StateNotifierProvider<_ChunksNotifier, AsyncValue<List<Chunk>>>((ref) {
  final api = ref.watch(apiProvider);
  return _ChunksNotifier(api, ref);
});

class _ChunksNotifier extends StateNotifier<AsyncValue<List<Chunk>>> {
  _ChunksNotifier(this._api, this._ref) : super(const AsyncValue.loading()) {
    _fetch();
    _timer = Timer.periodic(
      Duration(seconds: _ref.read(apiProvider).config.refreshSeconds),
      (_) => _fetch(),
    );
  }

  final StreamingApi _api;
  final Ref _ref;
  Timer? _timer;

  Future<void> _fetch() async {
    try {
      final chunks = await _api.getChunks(limit: 200);
      if (mounted) state = AsyncValue.data(chunks);
    } catch (e, st) {
      if (mounted && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Audio files (5s polling) ──

final audioFilesProvider =
    StateNotifierProvider<_AudioFilesNotifier, AsyncValue<List<AudioFile>>>(
        (ref) {
  final api = ref.watch(apiProvider);
  return _AudioFilesNotifier(api, ref);
});

class _AudioFilesNotifier extends StateNotifier<AsyncValue<List<AudioFile>>> {
  _AudioFilesNotifier(this._api, this._ref)
      : super(const AsyncValue.loading()) {
    _fetch();
    _timer = Timer.periodic(
      Duration(seconds: _ref.read(apiProvider).config.refreshSeconds),
      (_) => _fetch(),
    );
  }

  final StreamingApi _api;
  final Ref _ref;
  Timer? _timer;

  Future<void> _fetch() async {
    try {
      final audio = await _api.getAudioFiles(limit: 300);
      if (mounted) state = AsyncValue.data(audio);
    } catch (e, st) {
      if (mounted && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() => _fetch();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Stats (one-shot, manual refresh) ──

final statsProvider = StateNotifierProvider<_StatsNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  final api = ref.watch(apiProvider);
  return _StatsNotifier(api);
});

class _StatsNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  _StatsNotifier(this._api) : super(const AsyncValue.loading()) {
    _fetch();
  }

  final StreamingApi _api;

  Future<void> _fetch() async {
    try {
      final stats = await _api.getStats();
      if (mounted) state = AsyncValue.data(stats);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _fetch();
}

// ── Admin context (one-shot, manual refresh) ──

final adminContextProvider = StateNotifierProvider<_AdminContextNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  final api = ref.watch(apiProvider);
  return _AdminContextNotifier(api);
});

class _AdminContextNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  _AdminContextNotifier(this._api) : super(const AsyncValue.loading()) {
    _fetch();
  }

  final StreamingApi _api;

  Future<void> _fetch() async {
    try {
      final ctx = await _api.getAdminContext();
      if (mounted) state = AsyncValue.data(ctx);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _fetch();
}

// ── Cron history ──

final cronHistoryProvider = StateNotifierProvider<_CronHistoryNotifier,
    AsyncValue<List<dynamic>>>((ref) {
  final api = ref.watch(apiProvider);
  return _CronHistoryNotifier(api);
});

class _CronHistoryNotifier
    extends StateNotifier<AsyncValue<List<dynamic>>> {
  _CronHistoryNotifier(this._api) : super(const AsyncValue.loading()) {
    _fetch();
  }

  final StreamingApi _api;

  Future<void> _fetch() async {
    try {
      final data = await _api.getCronHistory(page: 1, perPage: 40);
      final entries = data['entries'] as List<dynamic>? ?? [];
      if (mounted) state = AsyncValue.data(entries);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _fetch();
}

// ── Ticker (1s updates for progress bars) ──

final tickerProvider = StreamProvider<DateTime>((ref) {
  return Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});
