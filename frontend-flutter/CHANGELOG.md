# UI Re-Architecture — v0.2.0

## Architecture Changes

### State Management: Manual → Riverpod
- Replaced per-screen `StatefulWidget` with manual `Timer` polling and `setState`
- All screens now use `ConsumerStatefulWidget` / `ConsumerWidget` with shared Riverpod providers
- Centralized polling in providers (`stream_providers.dart`), screens just `ref.watch()`

### Routing: Inline → Centralized
- Moved `GoRouter` config from `main.dart` into `routing/app_router.dart`
- Added fade transitions between all routes
- Added `/library` route (new screen)

### Navigation: Bottom Bar → Adaptive Shell
- Mobile: `NavigationBar` (bottom) with 4 tabs
- Tablet/Desktop: `NavigationRail` (side) with labels
- Persistent `MiniPlayerBar` at the bottom showing current chunk + audio with skip controls

### DI: Manual → ProviderScope
- `main.dart` no longer creates `StreamingApi` manually and passes it down
- `ProviderScope` wraps the app; `apiProvider` creates the API instance once

---

## New Files

| File | Purpose |
|------|---------|
| `providers/api_provider.dart` | Riverpod `Provider<StreamingApi>` |
| `providers/stream_providers.dart` | All polling/state providers (stream status, server status, system usage, chunks, audio, stats, admin context, cron history) |
| `routing/app_router.dart` | Centralized GoRouter with fade transitions |
| `screens/library_screen.dart` | Combined chunks + audio browser (was part of old HomeScreen) |
| `widgets/section_header.dart` | Reusable page header with gradient icon |
| `widgets/shimmer_loader.dart` | Skeleton loading placeholders |
| `widgets/gauge_widget.dart` | Circular gauge (CPU/Mem/GPU) with custom painter |
| `widgets/chunk_card.dart` | Rich video chunk card with cached thumbnail |
| `widgets/audio_card.dart` | Audio file card with progress bar |
| `widgets/mini_player_bar.dart` | Bottom bar showing now-playing + skip controls |
| `widgets/adaptive_grid.dart` | Responsive grid layout |
| `widgets/filter_bar.dart` | Search + sort dropdown toolbar |
| `widgets/platform_badge.dart` | Instagram/TikTok/YouTube colored badge |
| `widgets/animated_counter.dart` | Tween-animated number counter |
| `widgets/pagination_bar.dart` | Page prev/next navigation |

---

## Modified Files

### `main.dart`
- Wrapped with `ProviderScope`
- Uses `appRouter` from routing config
- Removed manual `StreamingApi` instantiation

### `screens/home_screen.dart`
- **Complete rewrite** — was a 1500-line monolith with 3 tabs (Dashboard/Videos/Audio)
- Now ~500 lines, dashboard-only: overview stats, quick action pills, collapsible HLS player, now-playing section
- Chunks + audio listing moved to `LibraryScreen`

### `screens/stats_screen.dart`
- Converted to `ConsumerStatefulWidget` using `statsProvider`
- Added `CachedNetworkImage` for model thumbnails
- Added `PlatformBadge` widget, rank badges for top 3 models
- Replaced manual pagination with `PaginationBar`
- Added staggered fade-in animations

### `screens/admin_screen.dart`
- Converted to `ConsumerStatefulWidget` using multiple providers
- Added circular `GaugeWidget` for CPU/Memory/GPU
- Removed manual `Timer` polling (handled by providers)
- Added staggered fade-in animations

### `screens/app_shell.dart`
- Added adaptive nav (bottom bar ↔ side rail based on screen width)
- Integrated `MiniPlayerBar`
- 4 tabs: Home, Library, Stats, Admin

### `widgets/glass_card.dart`
- Renamed `animate` field → `tapAnimate` to avoid shadowing `flutter_animate` extension
- Added tap-to-scale animation

### `theme/app_theme.dart`
- Made color constants public (removed `_` prefix)
- Added responsive breakpoints (`breakpointMobile`, `breakpointTablet`, `breakpointDesktop`)
- Added `NavigationBarThemeData`, `NavigationRailThemeData`

### `pubspec.yaml`
- Version bumped to `0.2.0+1`
- Added: `flutter_riverpod`, `flutter_animate`, `cached_network_image`, `shimmer`, `fl_chart`, `lucide_icons`

---

## Unchanged

- **Backend** — All 23 Flask API endpoints untouched
- **Models** — `StreamStatus`, `Chunk`, `AudioFile`, `SystemUsage`, `ServerStatus`
- **Services** — `ApiClient`, `StreamingApi`
- **Config** — `AppConfig` with dart-defines
- **Infrastructure** — Docker, nginx, Helm chart
