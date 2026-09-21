# Melodify Project Status

Last reviewed: **2026-09-21**. Baseline: Git commit `7b557f7` (Initial commit).
This is a source-code audit; implemented does not imply device-tested or release-ready.

## Documentation Maintenance Rule

PROJECT_STATUS.md must be updated whenever a feature, dependency,
architecture decision, configuration, screen, database/storage behavior,
playback behavior, test coverage, build behavior, or known issue changes.

Any coding task that changes project behavior is incomplete until
PROJECT_STATUS.md has been reviewed and updated when applicable.

For future updates: update the relevant current-state sections, add a new dated
changelog entry, and preserve previous changelog entries. Do not rewrite historical
entries. Record verification dates and distinguish source inspection from runtime evidence.

## 1. Project Overview

- **App:** Melodify, developed by **DMJ Labs** (also displayed in About).
- **Purpose:** A personal music player currently focused on local/user-owned music.
- **Framework:** Flutter/Dart with Material 3.
- **Platform focus:** Android. iOS, macOS, Linux, Windows, and web runners exist,
  but their presence does not establish working local discovery/playback support.
- **Stage:** Early functional local-player prototype with unfinished discovery and
  library UI. Package version is `1.0.0+1`; this is not evidence of a production release.
- No online catalog, streaming-service integration, account system, or downloader
  is implemented.

## 2. Technology Stack

| Component | Verified configuration |
| --- | --- |
| Installed Flutter | `3.47.2`, stable, revision `d3b14c8769`, from `flutter --version` |
| Installed Dart | `3.13.2` |
| Project Dart constraint | `^3.13.2` in `pubspec.yaml` |
| Lockfile SDK constraints | Dart `>=3.13.2 <4.0.0`; Flutter `>=3.44.0` |
| UI/state | Material 3; `StatefulWidget`, `ChangeNotifier`, `ListenableBuilder`, `StreamBuilder` |
| Playback | `just_audio`; application-managed queue |
| Local discovery | `on_audio_query_pluse` / `OnAudioQuery` |
| Persistence | `shared_preferences`, currently theme choice only |
| Tests/lints | `flutter_test`, `flutter_lints`; no integration-test suite |
| Android build | Gradle Kotlin DSL, AGP `9.1.0`, Gradle `9.3.1`, Java/JVM target 17 |

Flutter is not pinned through a repository SDK manager configuration. Installed
tool versions and SDK-derived Android defaults describe this review environment.

## 3. Project Architecture

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App/theme lifecycle, shared audio player/controller, tab shell, nested Library navigator, mini-player |
| `lib/playback/playback_controller.dart` | Song selection, source loading, playback commands, completion handling, player disposal |
| `lib/playback/playback_queue.dart` | Backend-independent generic queue, mode and shuffle history |
| `lib/library/local_music_library.dart` | Shared session collection, permission/query lifecycle, in-memory search helper |
| `lib/models/local_music_folder.dart` | Immutable folder membership, path normalization, grouping/sorting |
| `lib/screens/` | Home, Search, Library, Local Music, Folder, Now Playing, Settings, Themes, About |
| `lib/widgets/local_song_list.dart` | Shared song rows; reads player state and delegates selection |
| `lib/widgets/music_artwork.dart` | Decorative icon/gradient artwork; not extracted album art |
| `lib/theme/` | Base colors, theme IDs/palettes/Material styling, preferences controller |
| `test/` | Seven Dart unit/widget test files |
| `assets/` | Launcher source image and bundled `audio/test_song.mp3` |
| `android/` | Android manifest, Kotlin activity, resources and Gradle configuration |
| `ios/`, `macos/`, `linux/`, `windows/`, `web/` | Other platform runners and packaging scaffolding; unverified as music-player targets |
| `pubspec.yaml`, `pubspec.lock` | Dependency declarations/resolution, app version, bundled assets |
| `analysis_options.yaml` | Flutter lints; excludes build and platform directories |

The app injects controllers through constructors rather than a provider/container.
`MainScreen` owns a shared `LocalMusicLibrary`, injected into Search and through
Library into Local Music. It caches an immutable title-ordered song list, coalesces
concurrent loads, and exposes loading/ready/denied/failed state. Local Music derives
its folders from that collection. Loading starts on Search tab selection or after
Local Music's first frame, not on application startup. Successful loads (including
empty libraries) are reused for the session; retry reruns permission/query logic. Selection calls
`PlaybackController.selectSong`; controller notifications update song/mode UI,
while player streams update position, duration and play/pause UI. There is no
database, persistent queue, favorites store, or history store.
The bundled test MP3 has no playback entry point in `lib/`.

## 4. Playback Architecture

`_MainScreenState` constructs the sole application `AudioPlayer` and passes it to
one `PlaybackController`. Screens receive this controller or its existing player.
The controller owns disposal of the player and its player-state subscription.

- `PlaybackQueue<SongModel>` copies the displayed list, exposes immutable items,
  tracks an index (`-1` when empty), and supplies `currentSong` via `queue.current`.
  Selection locates the song by ID. Songs view supplies all discovered songs;
  Folder view supplies only that folder's ordered songs. Search supplies a snapshot
  of the current matching results in displayed relevance order; later query edits do not
  modify that playback queue or interrupt playback.
- Loading stops the player, attempts `setFilePath(song.data)`, then falls back
  to `setUrl(song.uri)` if file loading fails. A generation counter gates the final
  play call after asynchronous loading; it does not serialize every load operation.
- **Sequential:** next advances; at the end manual next does nothing and natural
  completion stops playback while retaining the current song/queue.
- **Repeat all:** next/previous wrap at queue boundaries.
- **Repeat one:** natural completion seeks to zero and plays again; manual next
  advances when possible and does not wrap at the last song.
- **Shuffle:** selects a random different index when there is more than one song.
  Previous follows history; next reuses forward history before drawing again.
  This is not a shuffled permutation: older songs can recur before every song plays.
- Modes are mutually exclusive, not independent shuffle/repeat flags. Shuffle
  toggles to/from sequential. Repeat cycles to repeat-all, repeat-one, sequential;
  invoking it from shuffle enters repeat-all. Selection/clear do not reset mode.
- Previous restarts the current track if position is **greater than three seconds**;
  otherwise it uses queue previous (first song remains first unless repeat-all wraps).
- A `ProcessingState.completed` listener advances/repeats/stops with a reentrancy guard.
- Play/pause uses the shared player; replay from completed state seeks to zero.
  Close stops playback, clears the queue and hides the mini-player.
- The mini-player includes title, artist fallback, play/pause, close, seek slider,
  elapsed/total duration and navigation to Now Playing. It appears when a song is selected.
- Now Playing includes seek, timing, previous/next, play/pause, shuffle and repeat;
  it shows a blank-state message when no song exists. There is no queue editor/view.

**Preserve these rules:** keep one shared player, never create screen-owned players,
route selection through the controller with the intended displayed queue, and do
not stop/dispose playback when navigating. Playback survives screen/tab navigation
because the shell retains ownership. This is distinct from guaranteed OS background
playback: no background audio service or media notification integration exists.

## 5. Local Music

`lib/library/local_music_library.dart` centralizes `OnAudioQuery.permissionsStatus()`, then
`permissionsRequest()` if needed, and `querySongs(sortType: TITLE, orderType:
ASC_OR_SMALLER)`. Discovery is delegated to the plugin's Android media query
mechanism (MediaStore audio queries in resolved `on_audio_query_plus_android`
`1.3.0`); the app does not recursively scan storage or import arbitrary files.

- Songs/Folders chips switch views over the same query result. Songs displays
  title, artist (fallback `Local Music`), duration when available, loading indicator,
  and source-based current/playing/paused highlighting.
- Folder grouping uses normalized **full direct-parent POSIX paths**, preserving
  case-sensitive identity and keeping identically named folders on different paths
  separate. Nested folders are separate entries, not recursive collections.
- Local `file:` URIs can be normalized; relative paths, content URIs and malformed
  paths cannot identify a folder. Those songs remain available in Songs; Folders
  explains missing paths and counts excluded songs where applicable.
- Folder names sort case-insensitively with full-path tie breaking. Folder songs
  sort by case-insensitive title, then path, then ID. Folder lists/memberships are immutable.
- Selecting a song builds the appropriate queue and starts shared playback.
  List interaction is disabled while a song load is pending; folder screen also
  guards overlapping selections. Scroll positions use `PageStorageKey`.
- UI covers initial loading, permission denial, repeated denial with instructions
  to use Android Settings, query error/retry, no songs, and unavailable folder paths.
  Load failures show a snackbar. There is no direct system-settings deep link.
- No user-selected sort, successful-list refresh control, live MediaStore listener,
  or persistent library cache is implemented. Fresh Local Music routes reuse the
  shared session collection; retry can reload after denial/failure.

## 6. Navigation and Screens

`MainScreen` retains Home/Search/Library with an `IndexedStack`. Library has a
nested `Navigator` and `NavigatorPopHandler`, so its child routes retain the shell
and mini-player. Now Playing is pushed from the shell onto the root navigator.

| Screen | Status | Working behavior and limitations |
| --- | --- | --- |
| Main shell | IMPLEMENTED | Three tabs, retained pages, nested Library navigation, conditional mini-player |
| Home | PARTIAL | Shared current-song play/pause; static greeting, Recently Played cards and three dummy song rows |
| Search | IMPLEMENTED | Relevance-ranked title/artist/album substring search, trimmed case-insensitive queries, shared library/error states and result-queue playback |
| Library | PARTIAL | Opens Local Music and Settings; chips, Liked Songs and Recently Played are presentation-only |
| Local Music | IMPLEMENTED | Permissions, discovery, Songs/Folders and queue selection; limitations in section 5 |
| Folder | IMPLEMENTED | Folder name/path, ordered songs and delegated playback; counts appear in the parent folder list |
| Now Playing | IMPLEMENTED | Shared transport, seek and mode controls; decorative artwork |
| Settings | IMPLEMENTED | Theme and About navigation only |
| Theme Settings | IMPLEMENTED | Six choices, previews, selected indicator and immediate application |
| About | IMPLEMENTED | Identity, bundled version and Flutter licenses page |

IMPLEMENTED refers to the listed scope, not completion of all possible features.

Search uses `searchLocalSongs` to filter and rank in memory on typing, without
MediaStore calls per keystroke. Best-match priority is title exact/prefix/contains,
then artist exact/prefix/contains, then album exact/prefix/contains (nine ranks).
Queries and metadata are trimmed and lowercased for matching. Equal ranks sort by
case-insensitive song title, then song ID, file path and original collection index
for deterministic ties. The shared collection is not reordered. Displayed ranked
results are also the playback queue order; selecting a result starts at its index. Null/blank and `<unknown>` artist or
album values are handled safely. Empty query shows a search hint rather than every
song; unmatched queries show **No songs found**. Loading, denied permission with
retry/settings instructions, query failure/retry, and empty library have separate
states. Results reuse `LocalSongList` with optional album text, existing fallback
artwork and the current theme. Taps are guarded during loading and playback errors
show a snackbar. `PlaybackController` and `PlaybackQueue` remain unchanged.

## 7. Theme System

`MelodifyThemeId` defines **Melodify Green** (default), **Ocean Blue**, **Purple
Night**, **Crimson**, **AMOLED Black**, and **Light**, each with a stable storage ID.
`MelodifyThemeController` restores `melodify_theme` from `SharedPreferences`.
Missing/invalid values or read errors fall back to green. Selection notifies
immediately and then persists; write failures leave the session selection active.

`MelodifyApp` owns this controller, calls asynchronous restore, and rebuilds
`MaterialApp(theme: controller.theme)` through `ListenableBuilder`. There is no
system-theme mode; green can appear before restoration finishes.

`MelodifyPalette` is a `ThemeExtension` with background, surface, elevated, primary,
highlight, text, secondaryText and muted semantic colors, accessed through
`context.palette`. `MelodifyTheme.forId` configures Material 3 components and text.
Light uses light brightness/dark text. AMOLED uses a true-black scaffold background
but dark-gray card/elevated surfaces. Decorative artwork gradients remain
separate from the page palette; artwork is placeholder iconography.

## 8. Settings and About

Settings displays the active theme name and opens Themes/About. No equalizer,
audio quality, storage, account or playback preferences are present.
About displays Melodify, DMJ Labs and the local-player description. It loads the
bundled `pubspec.yaml` with `rootBundle`, extracts `version:` with a regular
expression, and currently displays `1.0.0+1`. It does **not** query installed package
metadata, so build-name/build-number overrides would not be reflected. Missing
version text falls back to `Unknown`; asset-load failure has no explicit error UI.
Open Source Licenses calls Flutter's `showLicensePage`.

## 9. Android Configuration

Sources: `android/app/build.gradle.kts`, `android/settings.gradle.kts`,
`android/gradle.properties`, wrapper properties, and manifests/resources.

| Setting | Current value |
| --- | --- |
| Namespace/application ID | `com.example.melodify` (template ID; TODO to replace) |
| App label/activity | `Melodify`; Kotlin `MainActivity : FlutterActivity()` |
| SDK values | Delegated to Flutter: installed SDK defaults are min **24**, compile/target **36** |
| NDK | Delegated to Flutter; installed default `28.2.13676358` |
| Java/Kotlin JVM target | 17 |
| Android Gradle Plugin | `9.1.0` |
| Gradle wrapper | `9.3.1-all` |
| Kotlin plugin declaration | `org.jetbrains.kotlin.android` version `2.4.0`, `apply false` in settings; app does not explicitly apply it |
| Flutter plugins | Loader `1.0.0`; app applies `dev.flutter.flutter-gradle-plugin` |
| Flags | AndroidX enabled; `android.newDsl=false`, `android.builtInKotlin=false`, `kotlin.incremental=false` |
| Gradle JVM sizing | 8 GB heap, 4 GB metaspace, 512 MB reserved code cache |
| Release signing | Uses **debug** signing configuration; production signing TODO |
| Version | Flutter version name/code derived from package/build configuration |

Main manifest declares `READ_MEDIA_AUDIO`, `READ_MEDIA_IMAGES`, and
`READ_EXTERNAL_STORAGE` capped at API 32. The image permission is attributed by
the manifest comment to the query plugin's permission check; it is not an image
browsing feature. Debug/profile manifests add `INTERNET`; main does not explicitly
declare it. No application background playback service/receiver is declared.

Launcher generation is Android-only using `assets/icon/melodify_icon.png`, adaptive
background `#121212`, the same foreground image, and foreground inset 28. Raster
densities and adaptive XML are present under `android/app/src/main/res/`.
Android ignores `local.properties`, signing properties and keystore files; never
include their contents in documentation. SDK-derived defaults can change with Flutter.

## 10. Dependencies

Versions below are **declared constraints from `pubspec.yaml`**; resolved versions
are distinguished in the purpose column where useful.

### Runtime dependencies

| Package | Version | Purpose |
| --- | --- | --- |
| `flutter` | Flutter SDK | Framework/Material UI |
| `cupertino_icons` | `^1.0.8` | Declared icon package; no CupertinoIcons usage in current app; locked `1.0.9` |
| `just_audio` | `^0.10.6` | Shared audio backend; locked `0.10.6` |
| `on_audio_query_pluse` | `^3.0.7` | Song models, device query and permissions; locked `3.0.7` |
| `shared_preferences` | `^2.5.3` | Theme preference; locked `2.5.5` |

### Development dependencies

| Package | Version | Purpose |
| --- | --- | --- |
| `flutter_test` | Flutter SDK | Unit/widget testing |
| `flutter_lints` | `^6.0.0` | Analyzer rules; locked `6.0.0` |
| `flutter_launcher_icons` | `^0.14.4` | Android icon generation; locked `0.14.4` |

No database, background-audio service, package-info or application state-management
package is directly declared. `pubspec.lock` records transitive dependencies.

## 11. Tests

| File | Coverage |
| --- | --- |
| `test/playback_queue_test.dart` | 5 tests: queue replacement/order, sequential bounds, repeat-one manual/automatic distinction, repeat-all wrapping, seeded shuffle/history/clear |
| `test/local_music_folder_test.dart` | 5 tests: full-path identity, direct parents, POSIX/file-URI normalization, invalid paths, immutable membership |
| `test/local_music_folder_screen_test.dart` | 1 widget test: display/fallback/duration, delegated selection, load guard and safe pop without disposing shared fake player |
| `test/melodify_theme_controller_test.dart` | 4 tests: default/invalid ID, persistence/restore, palette/AMOLED/light properties, all selections |
| `test/settings_screen_test.dart` | 2 widget tests: theme navigation/application; About identity/version/license entry |
| `test/local_music_search_test.dart` | 17 tests: nine relevance ranks, alphabetical/deterministic ties, case-insensitive ranking, ranked display/queue/index integration, title/artist/album, case/whitespace, empty/unknown metadata, coalesced cached discovery, result queue/index/source loading, query-edit isolation, next/previous, library states/retry and shared Local Music loading |
| `test/widget_test.dart` | 1 widget test: About opens Flutter LicensePage; not a full app smoke test |

Latest `flutter test` result: **PASS — all 35 tests passed**, exit code 0 (2026-09-21).
Search tests use the real PlaybackController/PlaybackQueue with fake audio/query
backends. Native playback/permission dialogs, full-shell device integration and
background lifecycle are not covered; controller failure/race paths remain untested. iOS/macOS `RunnerTests` contain template empty
example tests; they are not music feature coverage and were not run.

## 12. Static Analysis

Latest `flutter analyze` result: **PASS — No issues found**, exit code 0 (2026-09-21).
No analyzer errors, warnings or informational issues were reported.
`analysis_options.yaml` includes Flutter lints and excludes `build/**` plus all
platform directories. Analysis success does not validate native Android builds.
Requested `dart format lib test` result: **26 files formatted, 0 changed on final run**, exit
code 0 (2026-09-21). SDK commands required execution outside the restricted sandbox;
the completed checks above used that access. Search implementation and tests changed
in this update; existing tests were preserved.

## 13. Build Status

**Release build not verified during this documentation update.** No release build
or `flutter clean` was run for this audit.

Existing local artifacts were inspected, not rebuilt or installed:

- `build/app/outputs/flutter-apk/app-release.apk`: 57,812,978 bytes, filesystem
  modified 2026-09-19 21:53:41 (local time).
- Release output metadata reports application ID `com.example.melodify`, version
  name `1.0.0`, code `1`, variant `release`, minimum SDK for dexing `24`.
- Existing debug APK: 91,111,919 bytes, modified 2026-09-02 23:45:05.

These files prove artifacts exist, not that they match today's source or that a
fresh build succeeds. No current native-build warnings were verified. Release
signing is still debug signing. Other platform builds and physical-device behavior
were not verified in this update.

## 14. Implemented Features

- [x] Android-oriented local song discovery with permission/retry states.
- [x] Songs/Folders browsing and deterministic folder grouping/sorting.
- [x] Shared local playback with file-path/URI fallback.
- [x] Displayed-list queues, next/previous, shuffle history and repeat modes.
- [x] Natural completion handling and seek controls.
- [x] Persistent-across-navigation mini-player and Now Playing.
- [x] Six immediately applied themes with saved preference.
- [x] Settings, About, bundled version and license navigation.
- [x] Android launcher icon configuration/resources.
- [x] Relevance-ranked local Search by title, artist and album with ranked result queues.
- [ ] Real recently played data.
- [ ] Favorites/playlists and persistent library/playback state.
- [ ] Background audio service, media notification and lock-screen controls.
- [ ] Real embedded album artwork.

## 15. Pending / Planned Features

**PARTIALLY IMPLEMENTED:** Home has a real shared transport control but mock music
content. Library has working Local Music/Settings links but inactive favorites,
history and playlist affordances. Artwork is
decorative rather than metadata-driven.

**PLANNED / recommended backlog, not implemented or committed to a schedule:**
Listening history/Home data, favorites, playlists, library refresh,
embedded artwork, queue restoration, background service/media controls and release
packaging. These are recommendations based on gaps; no separate roadmap was found.

## 16. Known Issues / Technical Debt

Source-confirmed limitations (not claims of reproduced device failures):

- Player load errors from local selection get a snackbar, but queue/current-song
  state is updated before loading succeeds and is not rolled back on failure.
  Next/previous/completion paths lack equivalent UI error handling; `play()` futures
  are unawaited without application error handling.
- The generation guard gates playback but does not cancel/serialize source loading.
  Transport actions can overlap pending operations; controller race/error behavior
  lacks tests. `close()` stops rather than unloads the source, while row selection
  derives from that source, so a row can remain highlighted after queue clearing.
- Shuffle and repeat cannot be combined. Shuffle history can grow throughout a
  session and does not guarantee every song plays before repetition.
- Library data and queue/history are memory-only. The shared discovery cache has
  no live refresh or permission-revocation observer. Newly added songs require a
  fresh session (or a retry path); Search uses simple substring matching, without
  fuzzy/accent-insensitive matching;
  background/lock-screen reliability is not implemented or verified.
- About reads bundled version text rather than installed build metadata.
- Android still uses the example application ID and debug release signing.
  Kotlin incremental compilation is disabled; the reason is not recorded.
- Other platform runners are scaffolding rather than verified targets. For example,
  the iOS plist has no music-library usage description and macOS entitlements have
  no user-selected-file access configuration. No alternate discovery flow exists.
- `README.md`, package description and web manifest retain template descriptions.
  The test MP3 remains bundled without a current playback caller.

Check results and any environment limitations are recorded in sections 11–13.
No unrelated playback/queue behavior or dependencies were changed for Search.

## 17. Important Development Rules

- Preserve the single shared player/controller lifecycle and navigation continuity.
- Keep queue ordering tied to the actual selected list; retain folder-only queues
  and test manual versus automatic mode behavior when changing playback.
- Keep local playback usable independently of any future online source work.
- Do not treat decorative screens, runner directories or an old APK as proof of
  implemented features or verified builds.
- Use semantic palette colors and stable stored theme IDs; preserve light/AMOLED behavior.
- Preserve existing functionality and add/update meaningful tests for behavior changes.
- Run formatting, analysis and relevant tests; record failures honestly. Avoid
  unnecessary `flutter clean` and expensive release builds for documentation alone.
- Never commit credentials, signing secrets or private machine configuration.
- Review this document for every behavior/configuration/dependency change and append
  dated history without rewriting previous entries.

## 18. Project Change Log

### 2026-09-21 — Initial verified project status baseline

**Added**
- `PROJECT_STATUS.md` with maintenance/changelog rules, architecture, feature
  status, configuration, validation scope and recommended next work.
- Current-state inventory: local discovery/folders, shared playback/queue modes,
  mini-player/Now Playing, six persistent themes, Settings/About and six test files.
  These application features predate this documentation entry; no implementation
  dates are inferred. Git contains an Initial commit dated 2026-09-21 (`7b557f7`).

**Changed**
- Established a maintained status reference separating working flows, placeholders,
  source-confirmed limitations and unverified runtime/build behavior.

**Fixed**
- No application fixes in this documentation update.

**Removed**
- Nothing.

### 2026-09-21 — Functional local-music Search

**Added**
- Shared session library with coalesced MediaStore loading and permission/error states.
- Live title/artist/album Search, empty/no-match states and retry handling.
- 13 focused tests; complete suite: 31 passing tests. Flutter analysis: no issues.

**Changed**
- Local Music and Search reuse the same discovered collection.
- Search result taps use the existing controller with a result-list queue snapshot;
  query edits leave playback untouched. Song rows optionally show album metadata.
- Updated current architecture, feature status, test coverage and remaining work.

**Fixed**
- Search input now produces playable local results instead of static content.

**Removed**
- Static genre cards from Search. No dependencies or existing tests removed.

### 2026-09-21 - Search relevance ranking

**Added**
- Four tests covering all nine ranks, alphabetical/deterministic ties, normalized
  matching and displayed ranked queue order with selection at index 3.

**Changed**
- In-memory Search now orders title, artist and album matches by exact match,
  prefix and substring priority, then case-insensitive title and deterministic ties.
- Ranked results flow through the existing playback controller and queue unchanged.
- Validation: formatting completed, analysis clean, all 35 tests passed.

**Fixed**
- Artist/album-only matches no longer precede stronger title matches.

**Removed**
- Nothing. Shared library and playback architecture remain intact.

## 19. Next Recommended Work

1. Add PlaybackController tests for load failure, completion, rapid transport/close
   interactions and the three-second previous boundary; then address confirmed failures.
2. Verify discovery, permissions and playback on Android devices, including URI
   fallback and navigation; record device/API-specific results.
3. Add explicit library refresh and validate permission changes against the session cache.
4. Add persistent listening history and replace Home/Library dummy recently played content.
5. Implement favorites/playlists with deliberate storage and queue semantics.
6. Add background playback and Android media notification/lock-screen controls
   while preserving shared-player ownership; test lifecycle behavior explicitly.
7. Add library refresh and embedded artwork; prepare production identity/signing
   and verify a fresh release build when release work is requested.

These remaining recommendations were not implemented during the Search update.
