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

## Flutter Web and Android Builds (Recommended)

To simplify building and deploying across local or Proxmox environments, we use a single unified deployment manager: `scripts/build-deploy-flutter.sh`. By default, it uses Docker, so you do not even need Flutter installed!

Before building, configure your IPs/URLs inside `scripts/flutter_config.env`.

### Interactive Mode (Simplest)
If you just run the script with no arguments, it provides a simple menu to choose what you want to do:

```bash
cd scripts/
./build-deploy-flutter.sh
```

### Scripted Mode
You can also bypass the menu by providing arguments. 
Available environments defined in `flutter_config.env`: `local`, `proxmox`.

**Build Web (Local Environment):**
```bash
scripts/build-deploy-flutter.sh --env local --target web
```

**Build Android APK (Proxmox production environment variables):**
```bash
scripts/build-deploy-flutter.sh --env proxmox --target apk
```

**Build Web and Serve Locally for Preview:**
```bash
scripts/build-deploy-flutter.sh --env local --target web --serve
```

**Build Web and Deploy to Proxmox Directly:**
```bash
scripts/build-deploy-flutter.sh --env proxmox --target web --deploy
```

**Build Locally Instead of using Docker:**
```bash
scripts/build-deploy-flutter.sh --env local --target apk --engine local
```

The compiled outputs will be saved to:
- Web: `frontend-flutter/build/web`
- APK: `frontend-flutter/dist/android/random-video-streamer-release.apk`
- AAB: `frontend-flutter/dist/android/random-video-streamer-release.aab`

### Local Flutter run (development)

If you just want to run the app natively for active code development without compiling release packages:

```bash
cd frontend-flutter
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://<server-ip>:8081 \
  --dart-define=HLS_URL=http://<server-ip>:8082/hls/stream.m3u8 \
  --dart-define=ENABLE_LIVE_STREAM=false
```

Optional arguments:

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
