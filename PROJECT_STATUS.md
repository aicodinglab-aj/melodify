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
| Persistence | `shared_preferences`, theme choice and capped playback history |
| Tests/lints | `flutter_test`, `flutter_lints`; no integration-test suite |
| Android build | Gradle Kotlin DSL, AGP `9.1.0`, Gradle `9.3.1`, Java/JVM target 17 |

Flutter is not pinned through a repository SDK manager configuration. Installed
tool versions and SDK-derived Android defaults describe this review environment.

## 3. Project Architecture

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App/theme lifecycle, shared audio player/controller, tab shell, independent Home/Library navigators, mini-player |
| `lib/playback/playback_controller.dart` | Shared playback, completion, successful-start history hook, error state and disposal |
| `lib/playback/playback_queue.dart` | Backend-independent generic queue, mode and shuffle history |
| `lib/library/local_music_library.dart` | Shared session collection, permission/query lifecycle, in-memory search helper |
| `lib/library/playback_history.dart` | History controller/store interface, SharedPreferences adapter and identifier resolution |
| `lib/models/local_music_folder.dart` | Immutable folder membership, path normalization, grouping/sorting |
| `lib/screens/` | Home, Search, Library, Local Music, Folder, Now Playing, Settings, Themes, About |
| `lib/widgets/local_song_list.dart` | Shared song rows; reads player state and delegates selection |
| `lib/widgets/music_artwork.dart` | Decorative icon/gradient artwork; not extracted album art |
| `lib/theme/` | Base colors, theme IDs/palettes/Material styling, preferences controller |
| `test/` | Nine Dart unit/widget test files |
| `assets/` | Launcher source image and bundled `audio/test_song.mp3` |
| `android/` | Android manifest, Kotlin activity, resources and Gradle configuration |
| `ios/`, `macos/`, `linux/`, `windows/`, `web/` | Other platform runners and packaging scaffolding; unverified as music-player targets |
| `pubspec.yaml`, `pubspec.lock` | Dependency declarations/resolution, app version, bundled assets |
| `analysis_options.yaml` | Flutter lints; excludes build and platform directories |

The app injects controllers through constructors rather than a provider/container.
`MainScreen` owns a shared `LocalMusicLibrary` and `PlaybackHistory`. Home, Search
and Local Music reuse the library; Home and PlaybackController share the history.
The history store interface separates persistence from Home UI for later migration.
LocalMusicLibrary caches an immutable title-ordered song list, coalesces
concurrent loads, and exposes loading/ready/denied/failed state. Local Music derives
its folders from that collection. Home starts library loading/history restoration
after its first frame; Search selection and Local Music reuse the same load/cache.
Successful loads (including empty libraries) are reused for the session; retry
reruns permission/query logic. Selection calls
`PlaybackController.selectSong`; controller notifications update song/mode UI,
while player streams update position, duration and play/pause UI. There is no
database, persistent queue or favorites store; a small identifier-only listening
history is persisted in SharedPreferences.
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
  modify that playback queue or interrupt playback. Home snapshots its displayed
  Recently Played or Recently Added subset (up to 10 songs) into the same queue;
  subsequent history reordering does not change that queue.
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
- PlaybackController arms a history candidate after source loading and records once
  the shared player reports both `playing` and `ProcessingState.ready`. Failed
  loading or play attempts before that state are not recorded. This hook covers
  all entry points, next/previous, automatic completion and repeat/resume without
  changing PlaybackQueue mode semantics.
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
nested `Navigator`; Home now has its own independent nested `Navigator`. Each
is wrapped by a `NavigatorPopHandler` with an active-tab callback guard. AppBar
Back pops the nearest stack; system Back pops only the active tab stack. Both
retain the shell and mini-player, including when switching tabs mid-navigation. Now Playing is pushed from the shell onto the root navigator.

| Screen | Status | Working behavior and limitations |
| --- | --- | --- |
| Main shell | IMPLEMENTED | Three tabs, retained pages, independent Home/Library route stacks, conditional mini-player |
| Home | IMPLEMENTED (V1) | Quick Access, persistent Recently Played, MediaStore Recently Added, shared play/pause and library/error states |
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
show a snackbar. Search still uses the shared PlaybackController/PlaybackQueue.

### Home V1 and listening history

- Quick Access stays on Home and pushes the existing Local Music screen onto
  Home's nested navigator. Back returns to Home; Library-origin navigation keeps
  its separate stack and returns to its own previous route. Local Music/Songs opens Songs; Folders
  sets `initialShowFolders`. The shell and mini-player stay present.
- Recently Played shows up to 10 available songs, newest play first, from a history
  capped at **50 unique identifiers**. Replays move an existing item to the front.
- `PlaybackHistoryStore` abstracts read/write operations. The default adapter uses
  the existing SharedPreferences dependency and key `melodify_recently_played_v1`.
  It stores a string list: `path:` plus the local path, otherwise `uri:`, otherwise
  `id:` plus the MediaStore ID. No audio or duplicated song metadata is stored.
- Restoration runs once; recording waits for restoration and serializes writes.
  Storage failures preserve session history and display a Home notice. History is
  resolved against current shared-library metadata; unavailable identifiers are
  hidden without deleting them (for example, temporarily unmounted storage).
- Recently Added uses the package's verified `SongModel.dateAdded` / `date_added`
  MediaStore field, descending. Ties use case-insensitive title, ID and path.
  Null, zero or negative dates are omitted; no dates are invented. Up to 10 songs
  appear, with an explanatory empty state when no valid dates exist.
- Home uses theme-aware horizontal song cards with existing fallback artwork. It
  listens to library, history and controller changes, not position ticks. One
  shared discovery load feeds both sections; there is no scanning or polling.
- Empty-library, permission denial, query failure/retry and empty-history states
  are explicit. A stale cached file that fails when tapped produces a snackbar.
  Failed transport loads and asynchronous play errors are caught; Home displays
  the controller error. A failed queue item is retained rather than auto-skipped.

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
| `shared_preferences` | `^2.5.3` | Theme preference and Recently Played identifiers; locked `2.5.5` |

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
| `test/home_v1_test.dart` | 24 tests: history order/dedup/cap/persistence/storage failures, restoration ordering, missing songs, added-date sorting, successful-start recording, deleted-file/manual/automatic transport handling, repeat/resume, both Home queues/indices, shortcuts, library error states and all six themes |
| `test/navigation_test.dart` | 8 full-shell widget tests: all three Home shortcuts return Home via AppBar/system Back, independent Library/Home folder stacks, shared player identity, queue retention and mini-player presence |
| `test/widget_test.dart` | 1 widget test: About opens Flutter LicensePage; not a full app smoke test |

Latest `flutter test` result: **PASS — all 67 tests passed**, exit code 0 (2026-09-21).
Search and Home tests use the real PlaybackController/PlaybackQueue with fake
audio/query backends; SharedPreferences persistence is tested with its mock store. Full-shell Back routing is tested with mocked platform channels. Native playback/permission dialogs, device integration and
background lifecycle are not covered. Source/play errors and completion are tested;
rapid overlapping controller load races remain untested. iOS/macOS `RunnerTests` contain template empty
example tests; they are not music feature coverage and were not run.

## 12. Static Analysis

Latest `flutter analyze` result: **PASS — No issues found**, exit code 0 (2026-09-21).
No analyzer errors, warnings or informational issues were reported.
`analysis_options.yaml` includes Flutter lints and excludes `build/**` plus all
platform directories. Analysis success does not validate native Android builds.
Requested `dart format lib test` result: **29 files formatted**, exit
code 0 (2026-09-21). SDK commands required execution outside the restricted sandbox;
the completed checks above used that access. Home/history implementation and tests changed
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
- [x] Home Quick Access using existing Songs/Folders navigation.
- [x] Persistent Recently Played (50 unique identifiers; Home shows 10).
- [x] Recently Added from shared MediaStore added-date metadata (up to 10).
- [ ] Favorites/playlists and persistent library/playback state.
- [ ] Background audio service, media notification and lock-screen controls.
- [ ] Real embedded album artwork.

## 15. Pending / Planned Features

**PARTIALLY IMPLEMENTED:** Library has working Local Music/Settings links but
inactive favorites, history and playlist affordances; real history is currently
available on Home. Artwork is
decorative rather than metadata-driven.

**PLANNED / recommended backlog, not implemented or committed to a schedule:**
Library history navigation, favorites, playlists, library refresh,
embedded artwork, queue restoration, background service/media controls and release
packaging. These are recommendations based on gaps; no separate roadmap was found.

## 16. Known Issues / Technical Debt

Source-confirmed limitations (not claims of reproduced device failures):

- Player load errors from local selection get a snackbar, but queue/current-song
  state is updated before loading succeeds and is not rolled back on failure.
  Next/previous/completion load errors and `play()` errors are caught and exposed
  through controller error state on Home; other screens do not yet share that error
  presentation. Failed queue items are not automatically skipped.
- The generation guard gates playback but does not cancel/serialize source loading.
  Transport actions can overlap pending operations; rapid-load race behavior
  lacks tests. `close()` stops rather than unloads the source, while row selection
  derives from that source, so a row can remain highlighted after queue clearing.
- Shuffle and repeat cannot be combined. Shuffle history can grow throughout a
  session and does not guarantee every song plays before repetition.
- Library data and the playback queue are memory-only; listening history persists. The shared discovery cache has
  no live refresh or permission-revocation observer. Newly added songs require a
  fresh session (or a retry path); Search uses simple substring matching, without
  fuzzy/accent-insensitive matching;
  background/lock-screen reliability is not implemented or verified.
- Recently Added depends on MediaStore added-date availability/accuracy and the
  session collection. Undated songs remain available in Songs/Search but are omitted
  from Recently Added. This is a library insertion date, not a release date.
- History resolution depends on the current library; moved/renamed files may lose
  their association, and replacement files at the same path may inherit it. Missing
  items remain stored within the 50-entry cap but are hidden. There is no history
  clearing UI or database. Storage failures may lose persistence across restarts.
- A ready/playing backend state is the history success signal; device-level audio
  output and process termination during a preferences write were not verified.
- About reads bundled version text rather than installed build metadata.
- Android still uses the example application ID and debug release signing.
  Kotlin incremental compilation is disabled; the reason is not recorded.
- Other platform runners are scaffolding rather than verified targets. For example,
  the iOS plist has no music-library usage description and macOS entitlements have
  no user-selected-file access configuration. No alternate discovery flow exists.
- `README.md`, package description and web manifest retain template descriptions.
  The test MP3 remains bundled without a current playback caller.

Check results and any environment limitations are recorded in sections 11–13.
Home V1 retains a single shared player and existing queue modes; no dependencies
or native platform configuration were changed.

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

### 2026-09-21 - Home Screen V1 with real local data

**Added**
- Home Quick Access, up to 10 Recently Played and 10 Recently Added songs.
- A 50-entry deduplicated persistent history with a replaceable store interface,
  serialized SharedPreferences writes and current-library identifier resolution.
- Successful ready/playing history hooks for shared playback, plus safe handling
  of stale/deleted files and asynchronous play errors.
- 24 tests covering history/storage, metadata sorting, Home queues, navigation
  callbacks, failure states and all six themes; full suite: 59 passing tests.

**Changed**
- Home loads/reuses the shared library after its first frame and observes history
  updates. Quick Access uses the existing Library navigator and Local Music views.
- Recently Added sorts verified positive MediaStore date_added values newest first;
  unavailable dates are omitted. Selected Home collections become queue snapshots.
- Flutter analysis is clean; formatting completed. No APK build or clean performed.

**Fixed**
- Home no longer presents fictional music/history; failed loads do not create history.

**Removed**
- Home demo song rows and placeholder recently played cards. No dependencies removed.

### 2026-09-21 - Preserve Home Quick Access entry point

**Added**
- Eight full-shell navigation tests covering three Home shortcuts, Library folder
  routes, independent retained stacks, and AppBar plus simulated system Back.

**Changed**
- Home owns a nested navigator under the existing shared playback shell. Quick
  Access pushes existing Local Music views there without switching tabs.
- System Back callbacks guard the active tab so inactive stacks cannot be popped.
- Validation: 67 tests pass; formatting completed; Flutter analysis clean.

**Fixed**
- Back from Home Quick Access returns Home instead of Library. Library-origin
  routes continue returning through their own stack; player ownership is unchanged.

**Removed**
- Nothing. Previous changelog entries are preserved.

## 19. Next Recommended Work

1. Add PlaybackController tests for rapid transport/close interactions and the
   three-second previous boundary; then address confirmed failures.
2. Verify discovery, permissions and playback on Android devices, including URI
   fallback and navigation; record device/API-specific results.
3. Add explicit library refresh and validate permission changes against the session cache.
4. Connect Library's inactive Recently Played entry to the existing history and
   consider history management controls.
5. Implement favorites/playlists with deliberate storage and queue semantics.
6. Add background playback and Android media notification/lock-screen controls
   while preserving shared-player ownership; test lifecycle behavior explicitly.
7. Add library refresh and embedded artwork; prepare production identity/signing
   and verify a fresh release build when release work is requested.

These remaining recommendations were not implemented during the Home V1 update.
