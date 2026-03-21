# Flutter Client (POC)

This is a starter Flutter app for controlling and monitoring the Random Video Clips Streaming Server.

It now has separate route-based pages:

- `/#/` Dashboard
- `/#/admin` Admin
- `/#/stats` Stats

## What is implemented

- Live HLS player (`video_player` + **`video_player_web_hls`** on web + **`hls.js`** in `web/index.html`) — **off by default** (`ENABLE_LIVE_STREAM=true` to enable)
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

Live stream toggle (default is **off**; set `true` to embed the player):

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

- Android: HLS works with ExoPlayer; cleartext HTTP is allowed in the template manifest for LAN/dev streams.
- **APK vs web UI port:** The Flutter **web** UI on **:8090** is only static files. The **API is still on :8081** (Flask). Build the APK with `API_BASE_URL=http://<server-ip>:8081`, **not** `:8090`. On the phone, open `http://<server-ip>:8081/api/status` in Chrome — if you get JSON, the app can use the same base URL. Rebuild the APK after adding `INTERNET` in `main` AndroidManifest if release builds had no network access.
- Web: Chrome/Firefox need **HLS.js** (bundled via `index.html` + `video_player_web_hls`). The HLS origin must send **CORS** headers for `.m3u8` and segment requests. **Mixed content** (HTTPS page + HTTP stream) is blocked by the browser unless you proxy over HTTPS.
- **LAN / `192.168.x.x`:** If the web build still has `localhost` in `API_BASE_URL` / `HLS_URL`, the client rewrites `localhost` / `127.0.0.1` to the **same host as the page** (e.g. opening `http://192.168.0.11:8090/` uses `http://192.168.0.11:8081` and `:8082` for HLS). Rebuild after pulling so this logic ships.
- iOS is intentionally out of scope for this setup.

## Next steps

- Add auth if you expose this server beyond LAN.
- Add dedicated screens for Stats/Admin APIs.
- Add pagination and search for chunks and audio.
- Add offline/error-state UX polish.
