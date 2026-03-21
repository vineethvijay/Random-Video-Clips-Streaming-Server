# Flutter Client (POC)

This is a starter Flutter app for controlling and monitoring the Random Video Clips Streaming Server.

## What is implemented

- Live HLS player (`video_player`) - currently disabled by default
- Stream status polling (`/api/stream-status`)
- System usage polling (`/api/system-usage`)
- Chunks list (`/api/chunks`)
- Actions:
  - Skip video (`/api/skip_to_next`)
  - Skip audio (`/api/skip_to_next_audio`)
  - Generate chunks (`/api/generate_chunk`)
  - Play chunk next (`/api/play_chunk`)

## Prerequisites

- Backend server running and reachable from your device/emulator/browser
- Docker installed

## Docker builds (recommended)

From repo root:

### Build web

```bash
scripts/flutter-web-build-docker.sh \
  http://<server-ip>:8081 \
  http://<server-ip>:8082/hls/stream.m3u8
```

Output:

- `flutter_client/build/web`

### Build Android APK

```bash
scripts/flutter-android-build-docker.sh \
  apk \
  http://<server-ip>:8081 \
  http://<server-ip>:8082/hls/stream.m3u8
```

Output:

- `flutter_client/dist/android/random-video-streamer-release.apk`

### Build Android App Bundle (Play Store)

```bash
scripts/flutter-android-build-docker.sh \
  aab \
  http://<server-ip>:8081 \
  http://<server-ip>:8082/hls/stream.m3u8
```

Output:

- `flutter_client/dist/android/random-video-streamer-release.aab`

Both scripts run `flutter create --platforms=android,web .` inside Docker, so platform folders are generated without local Flutter.

Live stream toggle:

```bash
ENABLE_LIVE_STREAM=true scripts/flutter-web-build-docker.sh
ENABLE_LIVE_STREAM=true scripts/flutter-android-build-docker.sh apk
```

## Local Flutter run (optional)

```bash
cd flutter_client
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://<server-ip>:8081 \
  --dart-define=HLS_URL=http://<server-ip>:8082/hls/stream.m3u8 \
  --dart-define=ENABLE_LIVE_STREAM=false
```

Optional:

```bash
--dart-define=REFRESH_SECONDS=5
```

## Notes by platform

- Android: HLS playback should work with network-reachable stream URL.
- Web: HLS support depends on browser capabilities and stream CORS/network reachability.
- iOS is intentionally out of scope for this setup.

## Next steps

- Add auth if you expose this server beyond LAN.
- Add dedicated screens for Stats/Admin APIs.
- Add pagination and search for chunks and audio.
- Add offline/error-state UX polish.
