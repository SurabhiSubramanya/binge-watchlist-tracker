# Binge — TV season tracking (Option A)

Standalone plan for the season-tracking work started **2026-09-27**. Companion to
[`2026-07-binge-fixes-and-enhancements.md`](2026-07-binge-fixes-and-enhancements.md);
that plan stays the running log of everything post-feature-complete — this doc is
the detail for this one multi-subtask feature, and each subtask is marked done here
as it merges.

## Context

Binge tracks each title as **one whole unit** — no episodes, no seasons (the dedup
key is `mediaType-tmdbId`, `MediaItem.swift:65`). For a TV show that means the only
temporal fact on screen is `first_air_date`: the detail meta line reads
`TV · July 15, 2016` (`MediaDetailView.swift:107`) and the grid caption shows the
premiere **year** (`LibraryView.swift:67`). So a returning show looks frozen at its
premiere, you can't tell a finished 5-season run from one still going, and — because
the "Upcoming" tag and the release reminder both key off `first_air_date`, which is
in the past for any show that has aired — **you never get reminded when a new season
drops.**

The user picked **Option A** (see the before/after mockup): keep one library entry
per show, but read the season data TMDB *already returns* on `tv/{id}` and stops
being discarded, so the detail screen shows run span / season count / status / when
the next season lands, and the Upcoming tag + reminder follow the next season instead
of the premiere. **Option B** (pick a specific season to track, breaking the one-entry
dedup) and **Option C** (per-season episode breakdown) were considered and are out of
scope for this plan.

## Approach

No new endpoint. The `tv/{id}` response Binge already fetches in two places —
`SearchView.enrich` on add and `MediaDetailView.refresh` on open — carries everything
Option A needs; we just decode more of it:

| TMDB field | Used for |
|---|---|
| `number_of_seasons` | "4 seasons" |
| `status` | "Ended" / "Returning" / "Canceled" |
| `last_air_date` | close of the run span ("2008–2013") |
| `next_episode_to_air` (`air_date`, `season_number`) | when the next season lands; drives Upcoming + reminder |

We deliberately **do not** decode the full `seasons` array — that's Option C, and
Option A gets everything it needs from the four scalars above.

**The one load-bearing idea** is an *effective release date* on `MediaItem`:

- **Movie** → `releaseDate` (unchanged).
- **TV** → `nextReleaseDate ?? releaseDate` — the next episode/season air date if TMDB
  has one, else fall back to the premiere.

`isUpcoming` and `ReleaseReminder` both switch from reading `releaseDate` to reading
this. That single indirection makes every case fall out correctly: an ended show
(`next` = nil, premiere in the past) is not upcoming and offers no reminder; a
returning show with a dated next season is upcoming and *does*; a not-yet-premiered
show still works via the fallback. Movies are completely untouched because their
effective date *is* `releaseDate`.

**Follow existing patterns.** Everything date-related goes through `ReleaseDate` (the
UTC floating-date calendar — reaching for `Calendar.current` is the off-by-one this
codebase exists to avoid). Pure, judgment-carrying logic (the effective-date rule, the
meta-line composer, the status mapping) is extracted into testable functions/computeds
rather than living in a view — the same move as `LibraryView.Tally` and
`MediaItem.move(to:)`. New `MediaItem` stored properties are **all optional / defaulted**
so SwiftData does a lightweight automatic migration of the real library already on the
phone (no mapping model) — this is a hard constraint, see Risks.

## Subtasks

Executed one at a time, each on its own branch off `main` (`feature/season-N-<slug>`),
compiled and tested before review, fast-forward merged on approval — same rhythm as the
enhancements plan. Bookkeeping (marking a subtask done here) is its own `docs:` commit on
`main`, not folded into the next branch.

### 1. Decode the TV season fields (wire → normalized) ✅
*Done 2026-09-27 · commit `a2da056` · branch `feature/season-1-tmdb-decode` · merged to `main`. Added `SeriesStatus` + the five normalized fields; TV-only, nil for movies. 55 tests green (was 52) — returning/ended fixtures, status mapping, nil-season assertions on the movie & sparse-TV paths.*

`Services/TMDBModels.swift`: extend `TMDBDetailsResponse` with `numberOfSeasons: Int?`,
`status: String?`, `lastAirDate: String?`, and a nested `nextEpisodeToAir` (`airDate`,
`seasonNumber`, `episodeNumber`, all optional — TMDB sends `null` for ended shows). Add a
small `SeriesStatus` enum mapping TMDB's status strings → a display label
("Returning Series" → "Returning", "Ended", "Canceled", "In Production", "Planned",
"Pilot"; unknown → passthrough). Extend `TMDBTitleDetails` with the normalized results
(`numberOfSeasons`, `seriesStatus`, `lastAirDate: Date?`, `nextReleaseDate: Date?`,
`nextSeasonNumber: Int?`) and map them in `normalized(mediaType:)` — **TV only; every one
stays `nil` for movies**, mirroring how `releaseDate` already picks `first_air_date` vs
`release_date`. Dates parse through `ReleaseDate.parse`.
Tests: expand `TMDBFixtures.tvDetails` and add two more TV fixtures — a **returning** show
with a dated `next_episode_to_air`, and an **ended** show with `next_episode_to_air: null`
— then assert the decode in `TMDBDecodingTests`. Movie decode must be unaffected.
- **Model:** Sonnet 5 — follows the established DTO + `normalized()` pattern closely; the only real care is the optional nesting and the status mapping.
- **Depends on:** none

### 2. Persist the fields + effective-date / upcoming / reminder logic ✅
*Done 2026-09-27 · commit `cb16ca7` · branch `feature/season-2-model-reminder` · merged to `main`. Five optional stored fields, `effectiveReleaseDate` (movie: release; TV: `nextReleaseDate ?? releaseDate`), and `isUpcoming` + `ReleaseReminder` both route through it. 61 tests green (was 55); new schema boots on the simulator without a container crash (definitive on-device migration check happens on install-over-the-top).*

`Models/MediaItem.swift`: add stored `numberOfSeasons: Int?`, `seriesStatus: String?`,
`lastAirDate: Date?`, `nextReleaseDate: Date?`, `nextSeasonNumber: Int?` — **all optional
with `nil` defaults in `init`** (migration-safe). Add a computed `effectiveReleaseDate`
implementing the movie/TV rule above, and reroute `isUpcoming` through it.
`Services/ReleaseReminder.swift`: `fireComponents` reads `item.effectiveReleaseDate`
instead of `item.releaseDate` — nothing else in that pure logic changes (the UTC
day-read, the past-guard, the want-to-watch guard all still apply, now to the effective
date).
Tests: `ReleaseReminderTests` — a returning TV item with a **future** `nextReleaseDate`
is eligible and fires on that day; an **ended** TV item (`next` = nil, past premiere) is
not eligible; a not-yet-premiered TV item with no `next` still works via the premiere
fallback; a **movie** behaves exactly as before. Add `isUpcoming` assertions for the same
cases.
- **Model:** Opus 4.8 — the correctness core. Reminders firing on the wrong day is the
  exact class of bug this codebase most guards against (floating dates, time zones, the
  past-boundary), and the SwiftData migration must be lightweight or it touches the real
  library on the phone. High cost of getting wrong.
- **Depends on:** 1

### 3. Populate the new fields on add and refresh ✅
*Done 2026-09-27 · commit `2c183e3` · branch `feature/season-3-write-paths` · merged to `main`. Shared `MediaItem.applySeasonData(from:)` called by `enrich` (add) and `refresh` (open); refresh's reminder resync now compares `effectiveReleaseDate` before/after. 64 tests green (was 61) — decode→normalize→apply chain for returning/ended/movie.*

`Views/SearchView.swift` (`enrich`) and `Views/MediaDetailView.swift` (`refresh`): copy
the new normalized fields from `TMDBTitleDetails` onto the `MediaItem`, alongside the
genres/overview mapping that's already there. **Reminder resync:** `refresh` currently
re-syncs the notification only when `releaseDate` changed
(`MediaDetailView.swift:412`); since the reminder now keys off `effectiveReleaseDate`,
capture that *before* the update and re-sync when the **effective** date changes (a new
season getting dated is exactly the case that must re-arm the reminder).
Tests: covered indirectly by subtask 2's pure logic; the wiring itself is verified in the
end-to-end run (add a returning show, confirm the fields populate and a reminder can be
set). No new unit test unless the resync check is extractable cheaply.
- **Model:** Sonnet 5 — mostly mechanical field copying, but the effective-date resync
  needs a correct before/after capture, so not rote.
- **Depends on:** 2

### 4. Compose the richer detail meta line
Add pure, testable display computeds to `MediaItem` (e.g. `runSpanText`,
`seasonCountText`, `seriesStatusLabel`, `nextReleaseText`) and a `detailMetaLine` that
assembles them for TV, joined by ` · `; movies keep `type · release date`. Point
`MediaDetailView.metaLine` (`:107`) at it. Composition intent:
- **Run span:** ended/canceled with a `lastAirDate` → `2008–2013` (or just `2008` if one
  year); returning/ongoing → premiere year (the status word carries "still going");
  not-yet-premiered → premiere year.
- **Seasons:** `5 seasons` / `1 season`, omitted when unknown (manual pluralization — the
  "1 MOVIES" trap from Change 4).
- **Status:** the `SeriesStatus` label when known.
- **Next:** when `nextReleaseDate` is upcoming → `Next: Season N · <medium date>` (drop
  the season when `nextSeasonNumber` is nil). Dates via `ReleaseDate.formatted(_,.medium)`.
Tests: a new `SeasonMetaTests` (or extend an existing suite) pinning the string across
ended / returning-with-next / returning-without-next / not-premiered / movie.
- **Model:** Sonnet 5 — fiddly but fully specified string formatting with unit tests; no
  architectural judgment beyond what's written here.
- **Depends on:** 2

### 5. Reflect seasons in the Library grid
`Views/LibraryView.swift`: the "Upcoming" badge is already `item.isUpcoming ? …`
(`:68`), so subtask 2 **lights it up for new-season-coming automatically** — verify, no
change. For the caption, pass a TV run-span (a compact `MediaItem.gridYearText`, e.g.
`2016–2022`) in place of the bare premiere year, keeping `MediaPosterView`'s two-line
caption height so the Fix 1 grid alignment can't regress. Seed a couple of the
`SampleLibrary` TV entries with the new fields so the scaffolded screenshots show the
feature. (Search results carry no season data — `search/multi` doesn't return it — so
the Search grid badge stays premiere-based; out of scope.)
- **Model:** Sonnet 5 — small and pattern-following, but it touches the shared poster cell
  whose height once caused the Fix 1 misalignment, so it wants care over Haiku.
- **Depends on:** 2, 4

## Risks & edge cases
- **SwiftData migration (highest).** The phone holds a real library. Adding stored
  properties is only a *lightweight* automatic migration if they're optional/defaulted —
  which is the design (subtask 2). A non-optional new property, or a `#Unique`/schema
  change, would force a mapping model and risk the on-device data. Keep every new field
  optional. Install **over the top** on the phone (never uninstall — that wipes the
  Keychain TMDB token, the standing gotcha).
- **`next_episode_to_air` is often `null`** for a returning show TMDB hasn't dated yet.
  Then there's no "Next: …", no Upcoming tag, no reminder — correct (we genuinely don't
  know when), but it means the reminder win only appears once TMDB has a date. Refresh-on-
  open (subtask 3) is what picks that up later.
- **Mid-season vs season premiere.** `next_episode_to_air` points at the next *episode*,
  which mid-run isn't a season premiere. Option A surfaces it as "Next: Season N · date"
  regardless — the season number is still accurate; we're not claiming it's a premiere.
  Refining to premiere-only is a possible follow-up, not part of this plan.
- **Floating dates.** Every new date (`lastAirDate`, `nextReleaseDate`) is a TMDB
  `yyyy-MM-dd` with no time — parse and read through `ReleaseDate` (UTC), never
  `Calendar.current`, or the run span / next-season day slips west of Greenwich.
- **Reminder churn on a weekly show.** As episodes air, `nextReleaseDate` advances each
  refresh and the reminder re-arms to the next one. Acceptable for Option A (one reminder
  per title, always pointing at the next airing); noted so it's not mistaken for a bug.

## Testing & verification
- **Per subtask:** unit tests as noted (decode fixtures in 1; reminder/upcoming logic in
  2; meta-line composer in 4). The current suite is 52 green and must stay green each step.
- **End-to-end (after subtask 3, and again after 5):** on the Simulator via the
  `-seed-sample-library` / detail scaffold tricks (kept out of the committed diff), then on
  the physical iPhone installed **over the top** — add a returning show and an ended show,
  confirm the meta line reads correctly for each, the Upcoming tag + reminder appear only
  for the one with a dated next season, and the Library grid reflects both. Watching the
  reminder actually fire is impractical to verify live; the pure `ReleaseReminder` tests
  cover the fire-day correctness (as they always have).
- **Migration check:** first launch of a build carrying subtask 2 must open the existing
  on-device library without loss — verify on the phone, not just a fresh Simulator install.

## Open questions
None blocking — Option A is chosen and its shape is settled. The only deferred judgment is
the mid-season "Next" phrasing (see Risks), which ships as-is and can be refined later.
