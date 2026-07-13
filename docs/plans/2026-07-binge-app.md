# Binge — personal movie & TV watch tracker (iPhone)

## Progress
Executed one subtask at a time; each is built, run on the iOS Simulator, reviewed,
approved, and merged to `main` on its own branch.

- ✅ **Subtask 1 — Project scaffold** · completed 2026-07-11 · commit `2750eff` (branch `feature/01-project-scaffold`, merged to `main`). Buildable SwiftUI app, asset catalog, gold accent, dark launch background, shared scheme. Verified running on iPhone 17 sim.
- ✅ **Subtask 2 — SwiftData model** · completed 2026-07-11 · commit `739d759` (branch `feature/02-data-model`, merged to `main`). `MediaItem` + enums + Codable `StreamingProvider` + composite unique key. Verified via DEBUG `ModelSelfCheck` round-trip on the sim (enums + provider array persist).
- ✅ **Subtask 3 — Settings store + Keychain token** · completed 2026-07-12 · commit `4604483` (branch `feature/03-settings`, merged to `main`). `Keychain` generic-password wrapper + `@Observable` `AppSettings` (token → Keychain, region → `UserDefaults` seeded from `Locale.current.region`, fallback `US`). Values canonicalize on assignment (token trimmed, region uppercased). Exposes `isConfigured` / `bearerToken`. Verified via DEBUG `SettingsSelfCheck` against the **real** sim Keychain: write → read back → overwrite → clear, plus the reload read-through a fresh `AppSettings` does on relaunch.
- ✅ **Subtask 5 — App entry + tab navigation + Settings screen** · completed 2026-07-12 · commit `32d99f0` (branch `feature/05-navigation`, merged to `main`). **Done out of order, before Subtask 4** (see below). `BingeApp` sets up the `ModelContainer` + injects `AppSettings`; `Views/ContentView` is the Library·Search·Settings `TabView` (first launch with no token opens onto Settings and badges the tab); `Views/SettingsView` is the real token + region screen; `Support/Theme` holds the shared ground colour. Library/Search are placeholders until 6/7. Verified on the sim **and end-to-end on a physical iPhone 13 Pro**.
- ✅ **Subtask 4 — TMDB networking** · completed 2026-07-12 · commit `c3aa5d4` (branch `feature/04-tmdb-service`, merged to `main`). `TMDBService` (`searchMulti` / `details` / `watchProviders`) + `TMDBModels`, Bearer auth read from `AppSettings` per call, typed `TMDBError` with `isTokenProblem`. **Added the project's first unit-test target** (`BingeTests`, Swift Testing) — 11 tests, green. Verified twice: `xcodebuild test` against saved sample JSON, *and* a live round-trip against real TMDB on the physical iPhone.
- ✅ **Subtask 6 — Library views** · completed 2026-07-12 · commit `a5dbc85` (branch `feature/06-library`, merged to `main`). `LibraryView` (Want/Watched segments, `LazyVGrid`, sort + Movies·TV filter, all in-memory over one `@Query`) and reusable `MediaPosterView` with a real no-artwork fallback. **Also fixed release-date correctness** (see below). Undated titles sink deliberately in the release-date sort rather than masquerading as 1970. 25 tests green; verified on the simulator *and* on the physical iPhone with seeded sample data.
- ✅ **Subtask 7 — Search & add** · completed 2026-07-12 · commit `d41e83f` (branch `feature/07-search`, merged to `main`). `SearchView` with a 350ms debounce (via `.task(id:)` cancellation), poster-grid results, add-to-Want/Watched, and a green "In Library" badge driven by the same composite key `MediaItem` dedups on. Adds save immediately and enrich genres + providers in a background pass. Deleted the temporary `TMDBCheckSection` and `SampleLibrary`'s launch-arg seeding. Verified end-to-end on the physical iPhone.
- ✅ **Subtask 9 — Release reminders** · completed 2026-07-12 · commit `da435ac` (branch `feature/09-reminders`, merged to `main`). **Done before 8**, which depends on it. Split into a *pure* `ReleaseReminder` (whether/when — every edge unit-tested: UTC release day so it can't fire a day early, time-zone-free `DateComponents` so it follows the user, past triggers refused, composite-key ids as the duplicate guard) and a thin `NotificationManager` shell over `UNUserNotificationCenter`. `reconcile(with:)` runs at launch and prunes drift **without** ever prompting for permission. 37 tests green.
- ✅ **Subtask 8 — Detail screen** · completed 2026-07-12 · commit `bfd8840` (branch `feature/08-detail`, merged to `main`). `MediaDetailView`: backdrop/poster/date/genres/overview, "Where to watch" provider logos (with an explicit *"Not available to stream in <region>"* state, not a blank), and actions — Want↔Watched, remove, refresh, reminder toggle. Library cells now tap through. Refresh follows a revised release date and re-syncs the reminder. **This also closed out Subtask 9's end-to-end verification** — the toggle scheduled a real notification on device, and the permission prompt fired on the toggle rather than at app launch.
- ✅ **Subtask 10 — Setup & run documentation** · completed 2026-07-12 · commit `d8cec31` (branch `feature/10-docs`, merged to `main`). `README.md`: TMDB token (the long **v4 Read Access Token**, not the v3 key — the mistake worth warning about), Simulator run, physical-iPhone run on a free Apple ID (personal team → Developer Mode → trust the profile → ~7-day re-sign), first-launch token/region/notification behaviour, a manual test checklist, and the gotchas the build turned up. Checklist wording was checked against the code, not the plan's prose (the sort menu reads *Recently added*, not "date added"), and the documented `xcodebuild test` command was run: 37 tests green.

> **✅ PLAN COMPLETE — all ten subtasks done, merged to `main` (head `d8cec31`).**
> This plan is closed. **Post-feature-complete work lives in
> [`2026-07-binge-fixes-and-enhancements.md`](2026-07-binge-fixes-and-enhancements.md)**
> — bugs found in real use and functionality beyond the original scope. This one
> stays scoped to the ten build subtasks.

> **The app is feature-complete and running on the user's iPhone 13 Pro:** token in
> the Keychain, search → add → library → detail → reminders, all against live TMDB.
> 37 tests green. The one thing nobody can verify yet is a reminder actually
> *arriving* on release day — see Risks.

> **Release dates are floating calendar dates, not instants.** TMDB publishes
> `"2024-02-27"` — no time, no zone. Subtask 4 originally stored them as *local*
> midnight, which silently shifts the displayed day by one if the phone changes
> time zone. Corrected in Subtask 6: stored as **UTC midnight** and always read
> back through a **UTC calendar**, so the day matches what TMDB published in every
> time zone. Anything touching `releaseDate` must go through `ReleaseDate` — never
> `Calendar.current` directly. Feeds straight into Subtask 9's reminder logic.

> **Order was changed: 5 was done before 4.** Subtask 4 is the first piece needing a
> *live* TMDB token to verify, but the Settings screen that accepts one only landed in
> Subtask 5 (which depends on 2+3 only, so it was already unblocked). Doing 5 first
> means 4 can be checked against real TMDB responses, not just saved sample JSON.

> **Plan gap found:** the plan named a Settings *tab* but never assigned a
> `SettingsView` file to any subtask (6/7/8 are Library/Search/Detail). It was built
> as part of Subtask 5, since token entry is what unblocks Subtask 4.

> **Risk retired:** the Keychain round-trip is verified on the *physical* iPhone, not
> just the Simulator (which doesn't model the team-prefixed keychain access group) —
> token saved, badge cleared, still configured after a cold relaunch. Free-signing
> device deploys now run headlessly from the CLI (`DEVELOPMENT_TEAM` is committed).

> Carry-over resolved: the placeholder `ContentView`, `ModelSelfCheck.swift`, and
> `SettingsSelfCheck.swift` were all deleted in Subtask 5 as planned.

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

### One hard environment constraint  — ✅ RESOLVED
*As planned:* **full Xcode is not installed** (only Command Line Tools), so nothing
could be built or run until the user installed it; all code was written to be
correct on inspection, with the first real compile happening on their machine.

*What happened:* Xcode 26.6 was installed during Subtask 1 and every subtask since
has been compiled, tested, and run — on the Simulator and on the physical iPhone.
`xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
because `xcode-select` still points at the Command Line Tools.

## Subtasks

### 1. Finish the Xcode project scaffold + asset catalog  ✅ DONE
Verify/complete `Binge.xcodeproj` (uses a file-system-synchronized group so
source files are auto-included). Create the `Binge/` source folder and
`Assets.xcassets` with `AppIcon`, `AccentColor`, and `Contents.json`. Confirm
build settings: deployment target 17.0, generated Info.plist, bundle id
`com.binge.Binge`, device family iPhone/iPad.
- **Model:** Sonnet 5 — the `.pbxproj` format is fiddly and unverifiable without Xcode, so it needs care even though it's small.
- **Depends on:** none

### 2. Define the SwiftData model  ✅ DONE
`Binge/Models/MediaItem.swift`: `@Model final class MediaItem` with `tmdbId`,
`mediaType` (movie/tv enum), `title`, `overview`, `posterPath`, `releaseDate`
(optional Date), `watchStatus` (wantToWatch/watched enum), `dateAdded`,
`streamingProviders` (array of a small `Codable` struct: name, logoPath, offer
type), `providersRegion`, and a `reminderScheduled` flag. Include a stable unique
key on `(tmdbId, mediaType)` to prevent duplicates.
- **Model:** Sonnet 5 — core data-modeling decisions (dedup key, Codable-in-SwiftData for providers) that everything else builds on.
- **Depends on:** 1

### 3. Settings store + Keychain-backed API token  ✅ DONE
`Binge/Support/AppSettings.swift` (an `@Observable`/`ObservableObject`) holding
the TMDB token and region. Token stored in **Keychain** via a tiny wrapper
(`Support/Keychain.swift`); region in `UserDefaults`, defaulting to
`Locale.current.region`. Expose "is configured" so the UI can prompt for the
token on first launch.
- **Model:** Sonnet 5 — small but security-adjacent (secret handling); worth getting the Keychain wrapper right.
- **Depends on:** 1

### 4. TMDB networking layer  ✅ DONE
`Binge/Services/TMDBService.swift` + `Services/TMDBModels.swift`. Async methods:
`searchMulti(query)` (decodes mixed movie/TV results, skips `person`),
`details(for:)`, and `watchProviders(for:region:)`. Bearer-token auth from
AppSettings, typed errors (missing token, network, decoding), and an image-URL
helper (`posterURL(path:size:)`). No third-party deps.
- **Model:** Sonnet 5 — standard API integration; the only subtlety is decoding the heterogeneous `search/multi` payload and the nested providers structure.
- **Depends on:** 2, 3

### 5. App entry point + root tab navigation  ✅ DONE (built before 4)
`Binge/BingeApp.swift` sets up the `ModelContainer` and injects `AppSettings`.
`Binge/Views/ContentView.swift` is a `TabView`: **Library**, **Search**,
**Settings**. First-launch: if no token, nudge the user to Settings.
Also shipped `Binge/Views/SettingsView.swift` (token entry + region picker),
which the plan never assigned to a subtask.
- **Model:** Haiku 4.5 — mechanical wiring of container, environment, and tabs.
- **Depends on:** 2, 3

### 6. Library views (lists, poster grid, sort & filter)  ✅ DONE
`Views/LibraryView.swift`: segmented control for **Want to Watch** / **Watched**,
a poster grid (`LazyVGrid`) driven by `@Query`. Sort menu (release date / date
added / title) and a Movies·TV·All filter — implemented as query sort/predicate
or in-memory sort of the fetched results. `Views/MediaPosterView.swift`:
reusable `AsyncImage` poster cell with placeholder + title fallback.
- **Model:** Sonnet 5 — the core UI surface; SwiftData query + sort/filter wiring and a reusable poster component.
- **Depends on:** 4, 5

### 7. Search & add flow  ✅ DONE
`Views/SearchView.swift`: search field with debounced queries to
`searchMulti`, results as a poster grid, and an **add** action that inserts a
`MediaItem` (default *Want to Watch*, with an option to add straight to
*Watched*). Fetch + store the provider snapshot on add. Reuse `MediaPosterView`.
Reflect items already in the library.
- **Model:** Sonnet 5 — debounce, async search, and insert/dedup logic against the store.
- **Depends on:** 4, 6

### 8. Detail screen  ✅ DONE (built after 9)
`Views/MediaDetailView.swift`: large poster, title, release date (with an
"upcoming" indicator when in the future), overview, and **where to stream**
(provider logos for the chosen region). Actions: move between Want/Watched,
remove, refresh providers, and toggle a release reminder. Refreshes the provider
snapshot on open (best-effort).
- **Model:** Sonnet 5 — the richest screen; ties together model mutations, live provider refresh, and the reminder toggle.
- **Depends on:** 4, 6, 9

### 9. Release-date reminders (local notifications)  ✅ DONE (built before 8)
`Services/NotificationManager.swift`: request authorization; schedule a local
notification at a title's release date for Want-to-Watch items with a *future*
date; cancel on watched/removed/date-change. Guard against past dates,
missing dates, timezone handling, and duplicate scheduling (keyed by item id).
- **Model:** Opus 4.8 — the most correctness-sensitive piece: date/timezone edges, the permission flow, and a schedule/cancel lifecycle that must stay in sync with model changes.
- **Depends on:** 2, 5

### 10. Setup & run documentation  ✅ DONE
`README.md`: how to (a) install Xcode, (b) create a free TMDB account and copy
the v4 Read Access Token, (c) open the project, run on the **Simulator**, and
(d) run on a **real iPhone with a free Apple ID** — selecting your personal team,
trusting the developer profile on-device, and the **~7-day re-sign** caveat —
plus granting notification permission. Include a short manual test checklist.
- **Model:** Haiku 4.5 — straightforward documentation of known steps.
- **Depends on:** 1–9

Things learned during the build that the README **must** carry:
- **Deleting the app wipes the TMDB token, not just the library.** Since iOS 10.3,
  removing an app removes its Keychain items too. Bit us once.
- **Free-signing device deploys run headlessly** now that `DEVELOPMENT_TEAM` is
  committed: `xcodebuild -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates`
  then `xcrun devicectl device install app` / `process launch`. No Xcode GUI needed
  after the one-time team selection.
- **Developer Mode must be on** on the iPhone, or `devicectl` reports the device as
  `connected (no DDI)`.
- **`xcodebuild test`** runs the 37-test `BingeTests` target (Swift Testing).
- Notification permission is requested **when the user flips a reminder toggle**,
  never at launch.

## Risks & edge cases
*Every risk below is now settled — how each actually landed is recorded in italics.*

- ~~**No build verification here.**~~ ✅ **Retired.** Xcode 26.6 was installed in
  Subtask 1 and everything has compiled and run since. *The hand-written `.pbxproj`
  — flagged as the highest-risk file, with a "regenerate the project from scratch"
  fallback — was accepted by Xcode first time; it only normalized it to
  `objectVersion = 70` (benign). The fallback was never needed, so the README
  doesn't carry it.*
- ~~**TMDB token required.**~~ ✅ **Handled.** *No token → the app opens on Settings
  with a badged tab; Search and the detail screen say what's missing instead of
  hanging. The token lives in the Keychain.*
- ~~**Region-specific streaming.**~~ ✅ **Handled.** *The detail screen shows an
  explicit "Not available to stream in \<region\>" rather than a blank (Subtask 8).*
- ~~**SwiftData + Codable providers.**~~ ✅ **Didn't bite.** *The array of Codable
  `StreamingProvider`s persists fine in the `@Model` — verified by round-trip on the
  Simulator in Subtask 2. The JSON-`Data`-with-computed-accessors fallback was never
  needed.*
- ~~**Notification correctness.**~~ ✅ **Handled, and it was the right call to worry.**
  *Splitting the pure `ReleaseReminder` (whether/when) from the `UNUserNotificationCenter`
  shell is what made the edges testable: UTC release day, time-zone-free trigger, past
  dates refused, composite-key duplicate guard. Pinned by tests.*
- **Free-signing 7-day expiry.** ⚠️ **Real, permanent, and now documented.** Not a
  bug — an Apple limitation. *The README warns about it, and notes that reinstalling
  over the top preserves the library and token.*
- ~~**TMDB rate limits / terms.**~~ ✅ **Fine at personal scale.** *Search is debounced
  350ms; the README carries TMDB's required attribution line.*

**The one thing still unverifiable by anyone:** that a release reminder actually
*arrives* at 9am on release day — that's real-world time passing. The decision behind
it is pinned by tests; the delivery isn't.

## Testing & verification  ✅ ALL DONE
- **Per subtask:** ✅ SwiftUI `#Preview`s ship for each view. Unit tests grew to a
  **37-test `BingeTests` target** (Swift Testing, added by hand in Subtask 4 — the
  project's first test target): TMDB decoding, library sort/filter, `ReleaseDate`,
  and `ReleaseReminder`. Green as of the Subtask 10 run.
- **End-to-end:** ✅ done, on the Simulator *and* on the physical iPhone 13 Pro —
  token in Settings → search → add to Want to Watch → poster + release date +
  providers on the detail screen → mark watched (moves lists) → reminder toggle on
  an upcoming title, which scheduled a real notification on device and fired the
  permission prompt at the toggle rather than at launch.
- **Hard-to-test:** ✅ live provider accuracy spot-checked against known titles in
  the user's region. ⚠️ **Not verifiable at all:** a reminder actually *arriving* at
  9am on release day — that needs real-world time to pass. Its logic is pinned by
  tests; its delivery isn't.
- **Reproducible by anyone else:** the README's manual test checklist walks the same
  end-to-end path on a fresh machine.

## Open questions
None blocking, and none opened during the build. Defaults chosen where unspecified,
all of which survived to the finished app: streaming region defaults to the device
locale (changeable in Settings); new items default to *Want to Watch*; the app icon
is a simple generated placeholder — say the word if you want real artwork, which
would be a natural first entry in the fixes & enhancements backlog.
