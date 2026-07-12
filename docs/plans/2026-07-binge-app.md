# Binge — personal movie & TV watch tracker (iPhone)

## Context
Binge is a personal iOS app for one user to track movies and TV shows they *want
to watch* and have *already watched*. Each title is tracked as a single unit —
no individual episodes, no ratings. For every title the app shows its
poster/artwork, its release date, and where it can be streamed. This is a
greenfield project: the working directory currently contains only a starter
`Binge.xcodeproj` (created in a false start before this plan) and no source code.

Confirmed requirements from the user:
- **Run target:** their own iPhone via a *free* Apple ID, plus the iOS Simulator
  for development. No paid Apple Developer account → **no iCloud sync**.
- **Extras beyond core:** release-date reminders (local notifications) and
  sort & filter. Everything free/cheap.

## Approach

### Platform & data — SwiftUI + SwiftData (local only)
Native **SwiftUI** with **SwiftData** for on-device storage. Rationale:
- Free with Xcode; no third-party dependencies to manage or pay for.
- SwiftData (iOS 17+) is the modern, first-party persistence layer — a few lines
  to define the model, automatic `@Query`-driven UI updates, no schema
  boilerplate. For a single-user local library this is the lowest-friction
  choice. (Alternative — Core Data — is more verbose with no benefit here;
  a JSON file would need hand-rolled querying/observation. SwiftData wins.)
- **No CloudKit/iCloud sync**, because the free signing path can't ship the
  CloudKit entitlement. The model is designed so sync could be added later if the
  user ever upgrades, but it's out of scope now.

Deployment target **iOS 17.0** (required for SwiftData). Fine for a modern
personal iPhone.

### Metadata source — TMDB API (free)
**The Movie Database (TMDB)** free API covers *all four* data needs from one
source: search (movies + TV), posters/backdrops, release/air dates, and
**streaming availability** via its `watch/providers` endpoint (JustWatch data).
- Auth: TMDB **v4 Read Access Token** sent as `Authorization: Bearer <token>`.
  Simpler than the v3 `api_key` query param and what TMDB now recommends.
- The token is entered in-app on a Settings screen (stored in Keychain), so no
  secrets are committed to source and the app needs no code edit to configure.
- Streaming providers are **region-specific**. The app stores/uses a region code
  (default = device region, e.g. `US`), user-changeable in Settings.
- Images via SwiftUI's built-in **`AsyncImage`** (`https://image.tmdb.org/...`) —
  no image library needed. A small in-memory cache is optional, not required.

### Networking — plain URLSession + async/await
No Alamofire or other dependency. `URLSession` with `async/await` and `Codable`
is enough for ~3 endpoints. Keeps the project dependency-free (nothing to install
via SPM, faster first build).

### Notifications — UserNotifications (local only)
Release-date reminders use `UNUserNotificationCenter` local notifications
scheduled on-device. No server, no push infrastructure, free. Scheduled when a
*Want-to-Watch* title has a future release date; cancelled when the title is
marked watched or removed.

### One hard environment constraint
**Full Xcode is not installed** (only Command Line Tools). Nothing in this
project can be *built or run* until the user installs Xcode from the Mac App
Store. All code will be written to be correct on inspection, but the first real
compile happens on the user's machine after Xcode is installed. This is called
out again in Risks and drives the final documentation subtask.

## Subtasks

### 1. Finish the Xcode project scaffold + asset catalog
Verify/complete `Binge.xcodeproj` (uses a file-system-synchronized group so
source files are auto-included). Create the `Binge/` source folder and
`Assets.xcassets` with `AppIcon`, `AccentColor`, and `Contents.json`. Confirm
build settings: deployment target 17.0, generated Info.plist, bundle id
`com.binge.Binge`, device family iPhone/iPad.
- **Model:** Sonnet 5 — the `.pbxproj` format is fiddly and unverifiable without Xcode, so it needs care even though it's small.
- **Depends on:** none

### 2. Define the SwiftData model
`Binge/Models/MediaItem.swift`: `@Model final class MediaItem` with `tmdbId`,
`mediaType` (movie/tv enum), `title`, `overview`, `posterPath`, `releaseDate`
(optional Date), `watchStatus` (wantToWatch/watched enum), `dateAdded`,
`streamingProviders` (array of a small `Codable` struct: name, logoPath, offer
type), `providersRegion`, and a `reminderScheduled` flag. Include a stable unique
key on `(tmdbId, mediaType)` to prevent duplicates.
- **Model:** Sonnet 5 — core data-modeling decisions (dedup key, Codable-in-SwiftData for providers) that everything else builds on.
- **Depends on:** 1

### 3. Settings store + Keychain-backed API token
`Binge/Support/AppSettings.swift` (an `@Observable`/`ObservableObject`) holding
the TMDB token and region. Token stored in **Keychain** via a tiny wrapper
(`Support/Keychain.swift`); region in `UserDefaults`, defaulting to
`Locale.current.region`. Expose "is configured" so the UI can prompt for the
token on first launch.
- **Model:** Sonnet 5 — small but security-adjacent (secret handling); worth getting the Keychain wrapper right.
- **Depends on:** 1

### 4. TMDB networking layer
`Binge/Services/TMDBService.swift` + `Services/TMDBModels.swift`. Async methods:
`searchMulti(query)` (decodes mixed movie/TV results, skips `person`),
`details(for:)`, and `watchProviders(for:region:)`. Bearer-token auth from
AppSettings, typed errors (missing token, network, decoding), and an image-URL
helper (`posterURL(path:size:)`). No third-party deps.
- **Model:** Sonnet 5 — standard API integration; the only subtlety is decoding the heterogeneous `search/multi` payload and the nested providers structure.
- **Depends on:** 2, 3

### 5. App entry point + root tab navigation
`Binge/BingeApp.swift` sets up the `ModelContainer` and injects `AppSettings`.
`Binge/Views/ContentView.swift` is a `TabView`: **Library**, **Search**,
**Settings**. First-launch: if no token, nudge the user to Settings.
- **Model:** Haiku 4.5 — mechanical wiring of container, environment, and tabs.
- **Depends on:** 2, 3

### 6. Library views (lists, poster grid, sort & filter)
`Views/LibraryView.swift`: segmented control for **Want to Watch** / **Watched**,
a poster grid (`LazyVGrid`) driven by `@Query`. Sort menu (release date / date
added / title) and a Movies·TV·All filter — implemented as query sort/predicate
or in-memory sort of the fetched results. `Views/MediaPosterView.swift`:
reusable `AsyncImage` poster cell with placeholder + title fallback.
- **Model:** Sonnet 5 — the core UI surface; SwiftData query + sort/filter wiring and a reusable poster component.
- **Depends on:** 4, 5

### 7. Search & add flow
`Views/SearchView.swift`: search field with debounced queries to
`searchMulti`, results as a poster grid, and an **add** action that inserts a
`MediaItem` (default *Want to Watch*, with an option to add straight to
*Watched*). Fetch + store the provider snapshot on add. Reuse `MediaPosterView`.
Reflect items already in the library.
- **Model:** Sonnet 5 — debounce, async search, and insert/dedup logic against the store.
- **Depends on:** 4, 6

### 8. Detail screen
`Views/MediaDetailView.swift`: large poster, title, release date (with an
"upcoming" indicator when in the future), overview, and **where to stream**
(provider logos for the chosen region). Actions: move between Want/Watched,
remove, refresh providers, and toggle a release reminder. Refreshes the provider
snapshot on open (best-effort).
- **Model:** Sonnet 5 — the richest screen; ties together model mutations, live provider refresh, and the reminder toggle.
- **Depends on:** 4, 6, 9

### 9. Release-date reminders (local notifications)
`Services/NotificationManager.swift`: request authorization; schedule a local
notification at a title's release date for Want-to-Watch items with a *future*
date; cancel on watched/removed/date-change. Guard against past dates,
missing dates, timezone handling, and duplicate scheduling (keyed by item id).
- **Model:** Opus 4.8 — the most correctness-sensitive piece: date/timezone edges, the permission flow, and a schedule/cancel lifecycle that must stay in sync with model changes.
- **Depends on:** 2, 5

### 10. Setup & run documentation
`README.md`: how to (a) install Xcode, (b) create a free TMDB account and copy
the v4 Read Access Token, (c) open the project, run on the **Simulator**, and
(d) run on a **real iPhone with a free Apple ID** — selecting your personal team,
trusting the developer profile on-device, and the **~7-day re-sign** caveat —
plus granting notification permission. Include a short manual test checklist.
- **Model:** Haiku 4.5 — straightforward documentation of known steps.
- **Depends on:** 1–9

## Risks & edge cases
- **No build verification here.** Xcode isn't installed, so nothing compiles in
  this environment. First real build is on the user's machine; expect to fix a
  few compile nits then. The hand-written `.pbxproj` is the highest-risk file —
  if Xcode rejects it, regenerate via `File ▸ New ▸ Project` and drop the source
  folder in. (Subtask 10 will note this fallback.)
- **TMDB token required.** Every network feature is dead until the user pastes a
  valid token. The UI must fail gracefully (clear "add your token" state), not
  crash or hang.
- **Region-specific streaming.** Providers differ by country and can be empty for
  some titles/regions — show a "not available to stream" state, not a blank.
- **SwiftData + Codable providers.** Storing an array of a Codable struct in a
  `@Model` works but is a known sharp edge; if it misbehaves, fall back to a
  JSON-encoded `Data` property with computed accessors.
- **Notification correctness.** Past/nil release dates, timezone conversion, and
  keeping scheduled notifications in sync with list changes are the easiest
  things to get subtly wrong — hence Opus on subtask 9.
- **Free-signing 7-day expiry.** Not a bug — an Apple limitation of free Apple
  IDs. Must be documented so the user isn't surprised when the app stops opening.
- **TMDB rate limits / terms.** Fine at personal scale; just don't hammer search
  (hence debounce).

## Testing & verification
- **Per subtask:** SwiftUI `#Preview`s for each view (2, 6, 7, 8) with sample
  data so screens render without a live token. Unit-test the TMDB decoders
  (subtask 4) against saved sample JSON, and the notification date logic
  (subtask 9) — these are the pieces with real logic.
- **End-to-end (on the user's machine, post-Xcode):** install Xcode → add token
  in Settings → search a known title → add to Want to Watch → confirm poster +
  release date + providers on the detail screen → mark watched (moves lists) →
  set a reminder on an upcoming title → verify it's scheduled → run once on the
  Simulator and once on the physical iPhone.
- **Hard-to-test:** live streaming-provider accuracy (depends on TMDB/region) —
  verify manually against a couple of known titles.

## Open questions
None blocking. Defaults chosen where unspecified: streaming region defaults to
the device locale (changeable in Settings); new items default to *Want to Watch*;
app icon will be a simple generated placeholder unless you want custom artwork.
