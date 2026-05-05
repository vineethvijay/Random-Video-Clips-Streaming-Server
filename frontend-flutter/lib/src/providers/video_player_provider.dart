import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import 'api_provider.dart';

/// Immutable snapshot of video-player state exposed to the UI.
class VideoPlayerState {
  const VideoPlayerState({
    this.controller,
    this.videoError,
    this.playerCollapsed = true,
  });

  final VideoPlayerController? controller;
  final String? videoError;
  final bool playerCollapsed;

  bool get isInitialized => controller?.value.isInitialized ?? false;

  VideoPlayerState copyWith({
    VideoPlayerController? controller,
    String? videoError,
    bool clearError = false,
    bool? playerCollapsed,
  }) {
    return VideoPlayerState(
      controller: controller ?? this.controller,
      videoError: clearError ? null : (videoError ?? this.videoError),
      playerCollapsed: playerCollapsed ?? this.playerCollapsed,
    );
  }
}

class VideoPlayerNotifier extends StateNotifier<VideoPlayerState> {
  VideoPlayerNotifier(this._config) : super(const VideoPlayerState()) {
    if (_config.enableLiveStream) {
      _createAndInit();
    }
  }

  final AppConfig _config;

  void _onControllerUpdate() {
    final c = state.controller;
    if (c == null) return;
    if (c.value.hasError) {
      state = state.copyWith(
        videoError: c.value.errorDescription?.isNotEmpty == true
            ? c.value.errorDescription
            : 'Playback error',
      );
    }
    // Trigger rebuild so the UI picks up isPlaying / volume / etc.
    state = state.copyWith();
  }

  Future<void> _createAndInit() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_config.hlsUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..addListener(_onControllerUpdate);

    state = state.copyWith(controller: controller, clearError: true);

    try {
      await controller.initialize();
      await controller.setLooping(true);
      // Do NOT auto-play — the user must click play.
      state = state.copyWith(clearError: true);
    } catch (e) {
      state = state.copyWith(videoError: 'Could not load stream.\n$e');
    }
  }

  // ── public API ──────────────────────────────────────────────────────────

  Future<void> play() async {
    final c = state.controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.play();
    } catch (e) {
      if (kIsWeb) {
        state = state.copyWith(videoError: 'Autoplay may be blocked ($e)');
      }
    }
  }

  Future<void> pause() async {
    await state.controller?.pause();
  }

  Future<void> togglePlayPause() async {
    final c = state.controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> setVolume(double v) async {
    await state.controller?.setVolume(v);
  }

  void toggleCollapsed() {
    final wasCollapsed = state.playerCollapsed;
    state = state.copyWith(playerCollapsed: !wasCollapsed);
    // If expanding and not yet initialized, retry.
    if (wasCollapsed && !state.isInitialized && state.videoError == null) {
      retry();
    }
  }

  Future<void> retry() async {
    final old = state.controller;
    old?.removeListener(_onControllerUpdate);
    await old?.dispose();
    state = VideoPlayerState(playerCollapsed: state.playerCollapsed);
    await _createAndInit();
  }

  @override
  void dispose() {
    state.controller?.removeListener(_onControllerUpdate);
    state.controller?.dispose();
    super.dispose();
  }
}

/// Global, non-auto-disposed provider so the stream persists across tab switches.
final videoPlayerProvider =
    StateNotifierProvider<VideoPlayerNotifier, VideoPlayerState>((ref) {
  final config = ref.read(apiProvider).config;
  return VideoPlayerNotifier(config);
});
