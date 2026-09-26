# Melodify Project Status

Last reviewed: **2026-09-26**. Baseline: Git commit `7b557f7` (Initial commit).
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
| Playback | `just_audio`, `audio_service`, `audio_session`; application-managed queue |
| Local discovery | `on_audio_query_pluse` / `OnAudioQuery` |
| Persistence | `shared_preferences`, theme choice, capped playback history, favorites and playlists |
| Tests/lints | `flutter_test`, `flutter_lints`; no integration-test suite |
| Android build | Gradle Kotlin DSL, AGP `9.1.0`, Gradle `9.3.1`, Java/JVM target 17 |

Flutter is not pinned through a repository SDK manager configuration. Installed
tool versions and SDK-derived Android defaults describe this review environment.

## 3. Project Architecture

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App/theme lifecycle, injected playback runtime, tab shell, independent Home/Library navigators, mini-player |
| `lib/playback/playback_controller.dart` | Shared playback, serialized source loads, paused recent-song restoration, completion/history hooks and disposal |
| `lib/playback/startup_playback_restoration.dart` | Runtime-owned startup coordinator waiting for restored history and ready library availability |
| `lib/playback/playback_queue.dart` | Backend-independent generic queue, mode and shuffle history |
| `lib/library/local_music_library.dart` | Shared session collection, permission/query lifecycle, in-memory search helper |
| `lib/library/playlists.dart` | Immutable playlist metadata, observable repository, store interface and versioned SharedPreferences JSON adapter |
| `lib/library/favorites.dart` | Observable favorites repository, store interface and SharedPreferences adapter |
| `lib/library/playback_history.dart` | History controller/store interface, SharedPreferences adapter and identifier resolution |
| `lib/models/local_music_folder.dart` | Immutable folder membership, path normalization, grouping/sorting |
| `lib/screens/` | Home, Search, Library, Local Music, Folder, Liked Songs, Playlists, Playlist Details/Add Songs, Now Playing, Settings, Themes, About |
| `lib/widgets/local_song_list.dart` | Shared song rows; player state, delegated selection, favorite hearts and playlist menus |
| `lib/widgets/music_artwork.dart` | Decorative icon/gradient artwork; not extracted album art |
| `lib/theme/` | Base colors, theme IDs/palettes/Material styling, preferences controller |
| `test/` | Fifteen Dart unit/widget test files |
| `assets/` | Launcher source image and bundled `audio/test_song.mp3` |
| `android/` | Android manifest, Kotlin activity, resources and Gradle configuration |
| `ios/`, `macos/`, `linux/`, `windows/`, `web/` | Other platform runners and packaging scaffolding; unverified as music-player targets |
| `pubspec.yaml`, `pubspec.lock` | Dependency declarations/resolution, app version, bundled assets |
| `analysis_options.yaml` | Flutter lints; excludes build and platform directories |

The app injects controllers through constructors rather than a provider/container.
`PlaybackRuntime` owns a shared `LocalMusicLibrary`, `PlaybackHistory`, `Favorites` and `Playlists`. Home, Search
and Local Music reuse the library; Home and PlaybackController share the history.
The history store interface separates persistence from Home UI for later migration.
LocalMusicLibrary caches an immutable title-ordered song list, coalesces
concurrent loads, and exposes loading/ready/denied/failed state. Local Music derives
its folders from that collection. After the first frame, the runtime-owned startup
coordinator loads history/library and prepares paused recent playback. Home also
ensures those shared resources are loaded; the existing load/restore coalescing
prevents duplicate work. Search selection and Local Music reuse the same load/cache.
Successful loads (including empty libraries) are reused for the session; retry
reruns permission/query logic. Selection calls
`PlaybackController.selectSong`; controller notifications update song/mode UI,
while player streams update position, duration and play/pause UI. There is no
database or persistent queue; identifier-only listening history and favorites plus playlist metadata/song identifiers
are persisted in separate SharedPreferences keys.
The bundled test MP3 has no playback entry point in `lib/`.

## 4. Playback Architecture

`PlaybackRuntime._initialize` constructs the sole application `AudioPlayer` with
`handleInterruptions: false` and passes it to one `PlaybackController`. The runtime
also owns one `MelodifyAudioHandler`, the shared stores/library and startup coordinator.
Screens receive this controller or its existing player. Only explicit runtime shutdown
disposes the controller/player; widget disposal and backgrounding do not.

- `PlaybackQueue<SongModel>` copies the displayed list, exposes immutable items,
  tracks an index (`-1` when empty), and supplies `currentSong` via `queue.current`.
  Selection locates the song by ID. Songs view supplies all discovered songs;
  Folder view supplies only that folder's ordered songs. Search supplies a snapshot
  of the current matching results in displayed relevance order; later query edits do not
  modify that playback queue or interrupt playback. Home snapshots its displayed
  Recently Played or Recently Added subset (up to 10 songs) into the same queue;
  subsequent history reordering does not change that queue. Liked Songs supplies
  its available newest-liked-first list at the selected index; later favorite
  changes do not modify the active queue. Playlist Details snapshots available
  songs in insertion order at the tapped index. Its Play button starts the first
  available song in sequential mode; Shuffle picks a starting song and uses the
  existing shared shuffle mode. Row taps preserve the current mode.
- Loading stops the player, attempts `setFilePath(song.data)`, then falls back
  to `setUrl(song.uri)` if file loading fails. Source loads and Close stops now
  share a serialized operation chain. Generation checks suppress superseded
  loads/publication/play calls so startup cannot overwrite a newer user choice.
  Native loads already in flight must finish before the newer source can load.
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
- Play/pause uses the shared player and only starts a source matching the loaded
  current song; replay from completed state seeks to zero. Close cancels pending
  restoration/loading, immediately clears the queue/hides the mini-player, and
  serializes its stop before any later selection loads.
- The mini-player includes title, artist fallback, play/pause, close, seek slider,
  elapsed/total duration and navigation to Now Playing. It appears when a song is selected.
- Now Playing includes seek, timing, previous/next, play/pause, shuffle and repeat;
  it also has a synchronized, theme-aware favorite heart and shows a blank-state message when no song exists. There is no queue editor/view.

**Preserve these rules:** keep one shared player, never create screen-owned players,
route selection through the controller with the intended displayed queue, and do
not stop/dispose playback when navigating. Playback survives screen/tab navigation
because the process/service runtime retains ownership. Background Playback V1 now
integrates the Android foreground media service; physical-device reliability remains
unverified. See Background Playback V1 below.

### Background Playback V1 (2026-09-26)

The UI previously owned playback lifetime and had no OS media session. It now uses
UI/system controls -> shared PlaybackController -> exactly one just_audio player.
PlaybackRuntime.initialize coalesces concurrent calls and registers the same handler
once before runApp. Runtime.start also coalesces restoration across widget remounts.
Hot reload/rebuild does not create another player. There is no fallback player.

MelodifyAudioHandler extends BaseAudioHandler and projects controller queue/current
song plus player state, playback events, duration and speed. It owns subscriptions,
not a second playback engine or independently advancing queue. MediaItem identity
uses the existing path -> URI -> MediaStore ID rule; metadata is transient. Queue
order and current index reflect Local Music, folders, Search, Favorites, playlists,
Recently Played or the paused startup queue. Queue item selection delegates back
to controller selection. State broadcasts occur on events, not position polling;
system progress extrapolates the published position/time/speed.

Android notification/lock-screen metadata includes title, artist fallback, optional
album, duration, position and optional artwork. Compact controls are Previous,
Play/Pause, Next; expanded controls also expose Stop. Seeking and queue/mode actions
are advertised where the OS supports them. Bluetooth/headset media buttons use the
same handler. Android/OEM presentation varies and has not been physically checked.
Previous restarts above three seconds, otherwise uses app queue history. Manual
Next advances even in Repeat One; natural completion repeats one, wraps Repeat All,
or stops at the sequential boundary. Shuffle/history remain application-owned;
shuffle and repeat are still mutually exclusive.

AudioSession uses music focus with pause-when-ducked. The one player disables its
automatic interruption handling so there is one explicit policy. Interruptions
pause; eligible transient endings resume only if music was active/requested and
no intervening user action, Close, disconnect or newer interruption invalidated
that resume. Unknown/permanent loss stays paused. Noisy wired/Bluetooth disconnect
pauses without later auto-resume. The app does not change routes or force focus.

Explicit app Close, system Stop or notification dismissal stops the player, clears
the queue/media item and publishes idle to stop the service/remove the notification.
Close invalidates pending startup/source work. Home/app switching, lock and task
removal do not call Close. Android uses androidStopForegroundOnPause=false to keep
a paused ongoing session eligible for background resume; this can retain a foreground
notification while paused. androidResumeOnClick=false prevents retained controls
after explicit Stop. OEM process termination/force-stop can still end playback.

Service initialization does not load a source or write history. Restoration remains
once-per-runtime, newest available/loadable recent song, paused at zero, with no
autoplay/history write. Same-session Close wins; a genuinely new process may restore
history paused again. Exact position/queue/mode are not persisted. History still
records only the existing ready/playing signal, never metadata or lifecycle events.
Favorites and playlist persistence/order/identity are unchanged.

Artwork extraction requests 256px JPEG thumbnails, rejects empty/invalid/>512KiB
payloads, validates decoding, and stores at most 16 cache files in an app temporary
subdirectory. Deleted thumbnails regenerate on a later lookup; missing/inaccessible
art falls back to text/icon. Late results cannot replace another track's metadata.
Audio is never copied for artwork. Service errors show a shell notice and keep the
same player; audio-session setup failure disables playback with a restart notice.
Missing source/play errors use the controller error state without history writes.

Review fixes: loading errors now publish error rather than indefinite loading;
pause during a pending load prevents autoplay; sequential completion clears play
intent; stale interruption resume is cancelled; metadata comparisons include duration
and artwork rather than MediaItem ID alone; local artwork URIs are valid filesystem
URIs; cache slots bound disk usage; handler disposal cancels subscriptions and closes
all owned subjects idempotently. Widget test setup/cleanup runs runtime work outside
the fake clock, and lifecycle tests use valid Flutter state transitions.

**Physical-device status: NOT VERIFIED. No APK build or flutter clean was run.**
Native Android/iOS builds were not executed. Automated tests use fakes/mocked channels
and do not establish real audio output, focus behavior or notification rendering.

Physical Android checklist (record device, OS/API, build and observed results):

- [ ] Start a song; press Android Home and switch apps; confirm continuous audio.
- [ ] Turn screen off and lock; confirm audio continues and lock-screen metadata,
      artwork, duration/progress and playing/paused state are correct.
- [ ] Notification Play/Pause, Previous (both sides of three seconds), Next and seek.
- [ ] Bluetooth/headset Play/Pause and Previous/Next; verify app queue semantics.
- [ ] Disconnect wired headphones/Bluetooth while playing; confirm pause/no speaker burst.
- [ ] Receive a call/simulate transient/permanent focus loss; confirm appropriate
      pause/resume and no resume after manual Pause, Close or disconnect.
- [ ] Return/unlock; Home, mini-player and Now Playing match system state/index.
- [ ] Verify shuffle history, Repeat One/All and sequential ending in background.
- [ ] Play from folders/Search/Liked Songs/playlists; verify order and index.
- [ ] Swipe UI task from Recents while playing and paused; record actual OEM behavior.
- [ ] Use Melodify Close/system Stop; verify audio/service notification stops and
      queue stays empty on same-runtime reopen.
- [ ] Kill/restart process; verify normal paused recent-song restoration, no autoplay.
- [ ] Delete a queued file/artwork or revoke availability; verify safe error/fallback.
- [ ] Record Android-version notification layout, dismissal/seek support, battery
      policy and foreground-service restrictions encountered (none observed yet).
- [ ] On physical iOS: verify local discovery/permissions, background audio, lock
      controls, route changes and interruption behavior before claiming iOS support.

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
| Home | IMPLEMENTED (V1) | Quick Access, persistent Recently Played, MediaStore Recently Added, paused recent-track startup restoration, shared play/pause and library/error states |
| Search | IMPLEMENTED | Relevance-ranked title/artist/album substring search, trimmed case-insensitive queries, shared library/error states and result-queue playback |
| Library | PARTIAL | Opens Local Music, Liked Songs, Playlists and Settings; Playlists chip also navigates; Songs/Favorites chips and Recently Played remain presentation-only |
| Local Music | IMPLEMENTED | Permissions, discovery, Songs/Folders and queue selection; limitations in section 5 |
| Folder | IMPLEMENTED | Folder name/path, ordered songs and delegated playback; counts appear in the parent folder list |
| Playlists | IMPLEMENTED (V1) | Newest-created list, available counts, create/name validation, details, rename and confirmed deletion |
| Playlist Details / Add Songs | IMPLEMENTED (V1) | Insertion-ordered available songs, Play/Shuffle, multi-select search, remove, shared Favorites; no manual reorder |
| Liked Songs | IMPLEMENTED | Available favorites, newest-liked first, shared playback queue, empty/unavailable/loading/error states |
| Now Playing | IMPLEMENTED | Shared transport, seek, mode controls and favorite heart; decorative artwork |
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

### Home Play startup restoration

- Root cause: the Recently Played identifiers restored successfully, but the
  shared controller queue/source remained empty. Home correctly disabled Play
  because it had no current song; no shared playback restoration existed.
- `PlaybackRuntime` owns `StartupPlaybackRestoration`; MainScreen requests its
  coalesced start after the first frame. Explicit runtime shutdown disposes it
  before the shared library/history/controller. The coordinator
  waits for history restoration and `LibraryStatus.ready`, regardless of their
  completion order. Permission/query retries can supply availability later.
- It resolves all up to 50 stored recent identifiers against the session library
  using the existing path -> URI -> MediaStore ID identity. No storage schema,
  Favorites, playlists or history-persistence behavior was changed.
- If a current controller song exists, or an explicit selection/Close has already
  occurred, startup does nothing. Otherwise `restoreRecentSongs` tries resolved
  songs newest-first using the existing shared player's file/URI loader.
- A successfully loaded source is explicitly paused and sought to zero before
  publishing the recent queue/current song. Missing-library identifiers and
  candidates whose sources fail to load are skipped without pruning stored
  history. The queue starts at index 0 with the successful candidate, followed
  by remaining resolved recent songs in newest-first order. It can contain up
  to 50 entries, while Home's Recently Played cards still display at most 10.
- Restoration never calls play or arms the history-recording candidate. Tapping
  Home Play starts the loaded source and then follows the existing ready/playing
  history rules. Home, mini-player and Now Playing observe the same controller;
  Home keeps no separate restored-song state. Existing queue mode is preserved.
- A serialized native source-operation chain plus generation checks handles a
  newer selection or Close during preload. Restoration is attempted once after
  readiness and is not repeated after playback, history changes or later Close.
  Empty/unavailable history leaves the queue empty and Home Play disabled.
- Limits: this reconstructs a Recently Played queue, not the exact last playlist,
  folder queue, position or mode across processes. No position persistence was
  added. Remaining older queue items use session-cache availability and may fail
  if files disappear afterward. All candidate load failures leave a safe empty
  state without a dedicated startup-error message. A slow native load delays a
  newer selection until it completes; no native cancellation/timeout was added.
  Physical Android startup/audio behavior remains unverified.

### Liked Songs / Favorites

- `Favorites` is a runtime-owned `ChangeNotifier`, injected into Local Music,
  folder rows, Search, Now Playing and Library's Liked Songs route. Shared
  `FavoriteButton` widgets observe the same instance; no screen owns a copy.
- `FavoritesStore` separates persistence from UI. `PreferencesFavoritesStore`
  stores a deduplicated string list under `melodify_favorites_v1`, using the
  existing history identifier strategy: `path:` plus the nonblank local path,
  otherwise `uri:`, otherwise `id:` plus the MediaStore ID. No audio or song
  metadata is duplicated, and no dependency was added.
- List position stores like order without invented dates. New likes prepend;
  repeated likes are no-ops; unlike then re-like moves the song to the front.
  Favorites have no history-style 50-song cap.
- Restoration runs once at shell startup. Mutations wait for pending restoration,
  then notify immediately before serialized writes. Storage failures keep session
  state and show a notice in Liked Songs or a snackbar after a failed heart action.
- Resolution uses the shared current library. Missing identifiers are retained
  but omitted from displayed songs and new queues. Moved files do not automatically
  reconnect; files restored at the same identifier reappear. Path replacements
  can inherit a favorite, as with listening history.
- Liked Songs copies the displayed available list through the existing
  `PlaybackController.selectSong`, starting at the tapped index. Unlikes never
  alter the active queue, position, mode or player. Existing next/previous and
  shuffle/repeat semantics apply. Heart taps do not trigger row playback.
- Outline/filled hearts use semantic theme colors across all six themes. Artwork
  remains the existing fallback. Home cards are unchanged; Home Quick Access
  opens Local Music with the shared favorites instance.
- Availability reflects the session discovery cache, not live filesystem checks.
  A file removed after discovery can still fail to load; Liked Songs catches the
  error and shows a snackbar. Refresh/live MediaStore observation and physical
  Android restart/playback verification remain future work. Pending writes are
  not guaranteed to finish if the process is forcibly terminated.

### User-created Playlists (V1)

- Library's Playlists entry/chip opens a nested Playlists screen, then Playlist
  Details and Add Songs. AppBar/system Back follows that stack and retains the
  mini-player. Song-menu dialogs close back to their Local Music, Folder, Search
  or Liked Songs entry point. Home Quick Access inherits the Local Music actions;
  Home's separate cards and Now Playing controls are unchanged.
- `PlaybackRuntime` owns/restores/disposes one `Playlists` ChangeNotifier and injects it
  alongside the shared library/controller/Favorites. Screens depend on repository
  methods, not preferences, so a future SQLite `PlaylistsStore` adapter can replace
  the current storage without rewriting every screen.
- Immutable `Playlist` metadata contains a stable random 128-bit hex ID, trimmed
  name, UTC creation timestamp and an ordered immutable string list of song keys.
  `PreferencesPlaylistsStore` stores version-1 JSON under `melodify_playlists_v1`.
  Only metadata/identifiers are saved, never audio or duplicated SongModel data.
- Song keys reuse the Favorites/history identity strategy: nonblank local `path:`,
  otherwise `uri:`, otherwise MediaStore `id:`. IDs are device-local, not content
  hashes. Moves are not automatically reassociated; replacing a file at the same
  path can inherit a saved association.
- Create/rename trim names, reject empty names and names over 80 UTF-16 code units,
  and reject case-insensitive duplicate names. Rename retains ID, creation order
  and song order. Deletion requires a confirmation that music files are retained.
- Playlists remain newest-created first by persisted list order. Song additions
  append in selection order with deduplication by song key. Re-adding existing
  songs is a no-op; removal affects only that playlist. No drag/reorder UI exists.
- Add Songs uses the shared library with title/artist/fallback artwork and checkboxes;
  multi-selection survives search, which reuses in-memory relevance ranking. No
  MediaStore query runs per keystroke. Already-present songs remain checked and
  disabled. Shared song overflow menus offer Add to playlist, including creation
  when no playlist exists; Details also offers Remove from playlist. Menus do not
  trigger row playback. Duration text yields to the menu in these compact rows.
- Details resolves available songs in stored order for display, count and playback.
  Missing identifiers remain persisted but never enter newly constructed queues.
  Empty/unavailable lists disable Play/Shuffle. Existing queues are snapshots:
  rename, removal, deletion, and Favorites edits leave active playback untouched.
- Playlist rows use the same central Favorites instance and theme-aware controls.
  All six themes and a 360-pixel phone layout are covered by widget tests.
- Mutations await initial restoration, notify UI before saving, and serialize
  immutable write snapshots. Save failures preserve session edits and display a
  notice; a later successful edit saves the current state. Read/format/version
  failures preserve the original preferences and block edits until a successful
  retry, avoiding replacement of unreadable data with an empty collection.
- Limitations: SharedPreferences rewrites the collection per edit and is intended
  for a modest local V1 library; no database, import/export, cloud sync, or manual
  ordering. Availability reflects the session cache, not live filesystem checks.
  Files removed after discovery can still fail playback with a visible error.
  Process termination during a write and Android device persistence/playback have
  not been verified. Missing entries cannot be individually managed until available.

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
| App label/activity | `Melodify`; Kotlin `MainActivity : AudioServiceActivity()` |
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
declare it. Background playback adds WAKE_LOCK, FOREGROUND_SERVICE and
FOREGROUND_SERVICE_MEDIA_PLAYBACK, the exported audio_service mediaPlayback service
and MediaButtonReceiver. The service has the MediaBrowserService intent filter,
and the receiver handles MEDIA_BUTTON. Notification icon ic_stat_music is retained
by res/raw/keep.xml. No new broad storage, Internet, battery-exemption or notification
runtime permission was added. iOS Info.plist enables UIBackgroundModes/audio;
iOS discovery and background behavior still require device verification.

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
| `audio_service` | `^0.18.19` | Android/iOS media session and background service; locked `0.18.19` |
| `audio_session` | `^0.2.4` | Explicit music focus/interruption policy; existing transitive dependency now direct |
| `path_provider` | `^2.1.6` | Temporary media artwork directory; existing transitive dependency now direct |
| `just_audio` | `^0.10.6` | Shared audio backend; locked `0.10.6` |
| `on_audio_query_pluse` | `^3.0.7` | Song models, device query and permissions; locked `3.0.7` |
| `shared_preferences` | `^2.5.3` | Theme preference, Recently Played/favorites identifiers and playlist metadata; locked `2.5.5` |

### Development dependencies

| Package | Version | Purpose |
| --- | --- | --- |
| `audio_service_platform_interface` | `^0.1.3` | Native method-channel service contract test on the Windows host; locked `0.1.3` |
| `flutter_test` | Flutter SDK | Unit/widget testing |
| `flutter_lints` | `^6.0.0` | Analyzer rules; locked `6.0.0` |
| `flutter_launcher_icons` | `^0.14.4` | Android icon generation; locked `0.14.4` |

No application database, package-info or state-management package is directly
declared. audio_service adds flutter_cache_manager and its HTTP/SQLite transitive
dependencies; Melodify collection persistence remains SharedPreferences. `pubspec.lock` records transitive dependencies.

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
| `test/favorites_test.dart` | 10 tests: like/unlike/dedup/order/re-like, preferences restoration, missing identifiers, restoration races/serialized saves, failure recovery, displayed queue/index/next/previous, queue isolation, Now Playing/Search synchronization, Local Music tap isolation, empty/unavailable states and six theme accents |
| `test/playlists_test.dart` | 11 tests: creation/identity/order/immutability, name validation, rename preservation, single/multiple additions/dedup, removal/deletion isolation, JSON persistence/restoration, missing identifiers, serialized restoration/writes, save failure recovery, read retry and malformed/newer data preservation |
| `test/playlist_screens_test.dart` | 11 widget tests: create validation, queue/index/Play/Shuffle/modes, removal isolation, rename/delete confirmation, multi-selection/search, all three required Add to playlist origins, Favorites synchronization, unavailable/permission states and six themes at phone width |
| `test/navigation_test.dart` | 11 full-shell widget tests: Playlist stack/shared player retention with AppBar and system Back; Library Liked Songs navigation/shared ownership/Back plus all three Home shortcuts return Home via AppBar/system Back, independent Library/Home folder stacks, shared player identity, queue retention and mini-player presence |
| `test/startup_playback_restoration_test.dart` | 20 tests: paused queue/index/source, Home Play/history hook, missing and stale files, empty/all-failed history, active-queue preservation, four modes, both readiness orders, permission retry, selection/Close races, persisted restart, next/previous and one-player construction guard |
| `test/background_playback_test.dart` | 33 tests: shared player/state/control projection, queue/index/modes, previous threshold, startup/Close races, history isolation, interruptions/noisy events, late resume suppression, missing files/artwork, bounded artwork cache, lifecycle/remount, playlist/favorites queues and static native contract |
| `test/playback_runtime_test.dart` | 1 native-channel contract test: concurrent startup registers once, shares player and does not autoplay |
| `test/widget_test.dart` | 1 widget test: About opens Flutter LicensePage; not a full app smoke test |

Latest `flutter test` result: **PASS — all 156 tests passed**, exit code 0 (2026-09-26).
Search and Home tests use the real PlaybackController/PlaybackQueue with fake
audio/query backends; SharedPreferences persistence is tested with its mock store. Full-shell Back routing is tested with mocked platform channels. Native playback/permission dialogs, device integration and
native background lifecycle are not covered; simulated widget background/remount is covered. Source/play errors and completion are tested;
Startup preload versus selection/Close races are covered with delayed fake loads;
broader native transport/completion/seek races remain unverified. iOS/macOS `RunnerTests` contain template empty
example tests; they are not music feature coverage and were not run.

## 12. Static Analysis

Latest `flutter analyze` result: **PASS — No issues found**, exit code 0 (2026-09-26).
No analyzer errors, warnings or informational issues were reported.
`analysis_options.yaml` includes Flutter lints and excludes `build/**` plus all
platform directories. Analysis success does not validate native Android builds.
Requested `dart format lib test` result: **49 files formatted**, exit
code 0 (2026-09-26). SDK commands required execution outside the restricted sandbox;
the completed checks above used that access. Background playback implementation and tests changed
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
- [x] Paused startup restoration from available Recently Played songs, enabling Home Play without autoplay.
- [x] Six immediately applied themes with saved preference.
- [x] Settings, About, bundled version and license navigation.
- [x] Android launcher icon configuration/resources.
- [x] Relevance-ranked local Search by title, artist and album with ranked result queues.
- [x] Home Quick Access using existing Songs/Folders navigation.
- [x] Persistent Recently Played (50 unique identifiers; Home shows 10).
- [x] Recently Added from shared MediaStore added-date metadata (up to 10).
- [x] Persistent Liked Songs with synchronized hearts and available-song queues.
- [x] Persistent user-created playlists, ordered membership, multi-select/search, row actions, rename/delete and shared Play/Shuffle queues.
- [ ] Persistent library/playback state.
- [x] Background audio service, notification/lock-screen transport and metadata integration (device verification pending).
- [x] Bounded embedded artwork thumbnails for the media session.
- [ ] Embedded artwork in the Flutter song/Now Playing UI.

## 15. Pending / Planned Features

**PARTIALLY IMPLEMENTED:** Library has working Local Music/Liked Songs/Playlists/Settings links but
inactive Songs/Favorites filter chips and history affordance; real history is currently
available on Home. Artwork is
decorative rather than metadata-driven.

**PLANNED / recommended backlog, not implemented or committed to a schedule:**
Library history navigation, playlist manual ordering/import/export, library refresh,
in-app embedded artwork, exact queue/position/mode persistence, device verification and release
packaging. These are recommendations based on gaps; no separate roadmap was found.

## 16. Known Issues / Technical Debt

Source-confirmed limitations (not claims of reproduced device failures):

- Player load errors from local selection get a snackbar, but queue/current-song
  state is updated before loading succeeds and is not rolled back on failure.
  Next/previous/completion load errors and `play()` errors are caught and exposed
  through controller error state on Home; other screens do not yet share that error
  presentation. Failed queue items are not automatically skipped during ordinary
  transport; startup restoration does skip failed candidates before publication.
- Source loading and Close stops are serialized, and startup races are tested.
  In-flight native loads cannot be cancelled, and broader seek/completion/transport
  races still need device validation. `close()` stops rather than unloads the source, while row selection
  derives from that source, so a row can remain highlighted after queue clearing.
- Shuffle and repeat cannot be combined. Shuffle history can grow throughout a
  session and does not guarantee every song plays before repetition.
- Library data and the exact playback queue are memory-only; startup reconstructs a
  recent queue from persisted history. Listening history, favorites and playlist metadata persist. The shared discovery cache has
  no live refresh or permission-revocation observer. Newly added songs require a
  fresh session (or a retry path); Search uses simple substring matching, without
  fuzzy/accent-insensitive matching;
  background/lock-screen integration is implemented but native reliability is not device-verified.
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
Home V1, Favorites and Playlists retain a single shared player and existing queue modes; no dependencies
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

### 2026-09-25 - Persistent Liked Songs / Favorites

**Added**
- Dedicated observable favorites repository/store and SharedPreferences adapter,
  identifier-only newest-liked-first persistence and serialized writes.
- Shared theme-aware favorite hearts in Local Music/folders, Search and Now Playing.
- Library Liked Songs route with available-song queues, empty/unavailable and
  permission/query/storage error states; missing identifiers remain stored.
- Ten focused favorites tests and one full-shell Library navigation test.

**Changed**
- Shell owns/restores/disposes one favorites instance and passes it to consumers.
- Updated Library, persistence architecture, implemented features, tests,
  limitations and recommended work. Existing changelog entries preserved.
- Validation (2026-09-25): dart format lib test completed (33 files),
  flutter analyze reports no issues, flutter test passes all 78 tests.

**Fixed**
- Library Liked Songs now opens a functional persistent collection.

**Removed**
- Nothing. Exactly one application AudioPlayer remains. No dependencies added,
  flutter clean run, or APK built. Android device verification remains pending.

### 2026-09-25 - Persistent user-created Playlists

**Added**
- Immutable playlist model and dedicated observable repository/store abstraction,
  versioned SharedPreferences JSON, stable IDs, ordered song keys and serialized saves.
- Library Playlists entry/chip, playlist list/details, validated create/rename,
  confirmed deletion, multi-select Add Songs with in-memory search, Play and Shuffle.
- Shared Add to playlist menus in Local Music, folders, Search and Liked Songs,
  and Remove from playlist in Details; all reuse central Favorites and playback.
- 24 tests: 11 storage tests, 11 playlist UI tests and two shell navigation tests.

**Changed**
- Updated Library, storage/identity/queue architecture, implemented features,
  tests, limitations and next work; preserved all earlier changelog entries.
- Validation: dart format lib test completed (41 files); flutter analyze reports
  no issues; flutter test passes all 102 tests. Exactly one AudioPlayer remains.

**Fixed**
- Playlist actions now provide immediate confirmation rather than queueing notices
  behind previous playlist actions. Navigation tests scroll to Library entries
  before tapping now that the collection list is longer.

**Removed**
- No existing features, tests or dependencies removed. No APK build or flutter clean.
- Native Android/device validation remains pending.

### 2026-09-25 - Paused startup playback restoration for Home Play

**Added**
- Shell-owned startup coordinator waiting for restored Recently Played and ready
  local availability before requesting shared-controller restoration.
- Paused recent-source preparation at position zero, newest available/loadable
  fallback and a recent queue; no startup autoplay or history write.
- 20 tests covering restoration, Home Play, missing files, empty history,
  preserved queues/modes, readiness order, permission retry, restart persistence,
  delayed selection/Close races and exactly one AudioPlayer construction.

**Changed**
- Serialized native source changes and Close stops, with generation checks to
  preserve explicit user actions during startup. Home continues to observe the
  existing shared controller; no Home-specific playback state was added.
- Documented architecture, fallback, queue behavior, limits and verification.
- Validation: dart format lib test completed (43 files); flutter analyze reports
  no issues; full flutter test suite passes all 122 tests; diff checks passed.

**Fixed**
- Home Play no longer remains disabled after restart when a recent song can be
  restored. Startup preparation does not replace an existing active queue.

**Removed**
- Nothing. Prior changelog entries and persistence schemas remain unchanged.
- Exactly one AudioPlayer remains. No flutter clean or APK build was run.

### 2026-09-26 - Background Playback V1

**Added**
- Process-lifetime PlaybackRuntime, MelodifyAudioHandler, explicit audio-session
  interruption/noisy-output policy and bounded safe media artwork cache.
- Android foreground media service, notification/lock-screen/media-button controls,
  AudioServiceActivity, service/receiver/permissions, retained notification icon;
  minimal iOS audio background mode and generated macOS plugin registration.
- audio_service 0.18.19; direct audio_session 0.2.4/path_provider 2.1.6;
  audio_service_platform_interface 0.1.3 as a test dependency.
- 34 tests covering handler/runtime controls, synchronization, lifecycle, focus,
  restoration, queue modes, history isolation, artwork/error handling and ownership.

**Changed**
- Runtime owns the existing single player/controller and shared stores independently
  of widgets. MainScreen injects them; both seek sliders route through the controller.
- PROJECT_STATUS current architecture, dependencies, verification and physical-device
  checklist updated; all prior changelog entries retained.
- Validation (2026-09-26): flutter pub get succeeded; dart format lib test (49 files);
  flutter analyze clean; full flutter test passes 156 tests; diff/static checks pass.

**Fixed**
- Pending-load pause, stale interruption-resume races, loading-error publication,
  completion play intent, metadata equality, artwork file URI/cache bounds and
  handler stream cleanup. Explicit Close remains authoritative over restoration.

**Removed**
- UI-owned playback disposal. No existing feature/history entry removed.
- Exactly one production AudioPlayer constructor and one AudioService.init remain.
- No flutter clean or APK build. Physical Android/iOS verification is pending.

## 19. Next Recommended Work

1. Extend PlaybackController coverage beyond startup races to rapid seek/completion/
   transport interactions and the three-second previous boundary; verify on devices.
2. Verify discovery, permissions and playback on Android devices, including URI
   fallback and navigation; record device/API-specific results.
3. Add explicit library refresh and validate permission changes against the session cache.
4. Connect Library's inactive Recently Played entry to the existing history and
   consider history management controls.
5. Validate playlist/favorites persistence and moved/deleted-file behavior on
   Android devices; consider manual playlist ordering and import/export afterward.
6. Physically verify Background Playback V1 using the checklist above, especially
   OEM task-removal, paused foreground sessions and focus/route behavior.
7. Add library refresh and embedded artwork; prepare production identity/signing
   and verify a fresh release build when release work is requested.

These remaining recommendations require follow-up beyond the Background Playback V1 implementation.
