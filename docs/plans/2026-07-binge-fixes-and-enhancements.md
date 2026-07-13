# Binge — fixes & enhancements

Companion to [`2026-07-binge-app.md`](2026-07-binge-app.md), which covers the ten
subtasks that built the app. That plan is closed once Subtask 10 (docs) lands;
**everything after feature-complete lives here** — bugs found in real use, and
functionality added beyond the original scope.

## Workflow
One bug or change at a time, each on its own `fix/NN-name` branch off `main`,
built and run before review, fast-forward merged once approved. Same rhythm as
the subtasks — no batching, even for small related fixes.

## Fixed

### Fix 1 — Poster cells misaligned in the library grid ✅
*Fixed 2026-07-12 · commit `1d42913` · branch `fix/01-poster-alignment` · merged to `main`*

**Symptom.** Posters in the Library grid didn't line up — some sat higher, some
lower, within the same row. Years were staggered too.

**Cause.** `MediaPosterView` captions each poster with `Text(title).lineLimit(2)`.
A title fitting on one line produced a *shorter cell* than one wrapping to two.
A `LazyVGrid` row is as tall as its tallest cell and vertically **centres** the
others, so short-title cells sank half the difference — poster, title and year
with them.

**Fix.** `.lineLimit(2, reservesSpace: true)` on the caption: it always occupies
two lines' height, so every cell is the same height and there is nothing left for
the grid to centre. One line changed.

**Notes worth keeping:**
- `alignment: .top` on the `GridItem` is *not* the fix, though it looks like it.
  In a `LazyVGrid` that parameter sets **horizontal** alignment within the column,
  not vertical. Equalising cell height is what actually works.
- `MediaPosterView` is shared with Search, so this fixed the Search results grid
  at the same time.
- Pure layout — no logic to unit-test. Verified by before/after screenshots on the
  Simulator and confirmed by the user on the physical iPhone. The 37 existing tests
  stayed green.
- **Screenshotting the grid needs scaffolding.** The Simulator has no TMDB token
  and an empty library, and there's no CLI way to type one in. To capture the grid,
  `BingeApp` was temporarily pointed at `SampleLibrary.previewContainer` behind a
  `-seed-sample-library` launch argument (with `AppSettings.preview(token:)` so it
  opens on Library, not Settings), then reverted before commit. Re-do this trick
  rather than reinventing it — but keep it **out** of the committed diff.

### Fix 2 — Posters sometimes don't load in the library grid ⏳
*Fixed 2026-07-12 · branch `fix/02-poster-loading` · awaiting review*

**Symptom.** A poster is missing from the Library grid — a grey fallback cell —
but opening that same title's detail page shows the artwork perfectly. Different
titles each time, and it comes and goes.

**Cause.** *Not* a data problem, which is what the symptom makes it look like.
The grid and the detail page both render `MediaPosterView`, both pass the same
`posterPath`, and both build the same `w342` URL — so when the detail page shows
the art, the grid was asking for a URL that works. The failure was in the
*loading*, and `MediaPosterView` handed its URL straight to `AsyncImage`, which
has two properties a scrolling grid can't live with:

- **A failed fetch is final.** `AsyncImage` reports `.failure` and stops. It never
  retries, so one dropped connection burns the cell for as long as it lives.
- **It has no cache.** Every time a `LazyVGrid` rebuilt a cell the image was
  fetched *again* — so scrolling produced a fresh burst of requests, and every one
  of them was a new chance to draw the short straw above.

Together those explain everything: the grid fires 20+ simultaneous requests when
it appears and re-fires them as you scroll (many chances to fail, no recovery),
while the detail page makes one request on a screen that stays put (it succeeds,
and it's the *same URL*). The old code even had a comment rationalising it —
"a retry won't help" — which conflated *TMDB has no artwork for this* (`posterPath`
is nil, a different branch entirely) with *this fetch failed*. A retry is exactly
what helps.

**Fix.** `ArtworkLoader` (+ `ImageCache`) and a `RemoteImage` view to replace
`AsyncImage` in `MediaPosterView`:
- **Retries** transient failures — network errors, 5xx, 429 — three attempts with
  a growing backoff, rather than giving up on the first stumble.
- **Doesn't retry** a 404 or undecodable bytes: TMDB genuinely doesn't have that
  artwork, and the cell should reach its fallback promptly instead of stalling.
- **Caches** decoded images in an `NSCache` (evictable under memory pressure, so
  this can't get the app killed), and the bytes in a 256 MB on-disk `URLCache`.
  A cache hit resolves in `init`, *before* the first render, so a recycled cell
  paints its poster immediately instead of flashing a spinner over an image the
  app already has.
- **Treats cancellation as not-a-failure.** A cell scrolling off mid-fetch cancels
  the load; that leaves the view `.loading` and `task(id:)` restarts it if the cell
  comes back. `AsyncImage` counted this as `.failure` — a permanent hole in the grid.

**Notes worth keeping:**
- Artwork gets its **own** `URLSession` with its own cache. Deliberate:
  `URLSession.shared` is what `TMDBService` uses, and putting an HTTP cache on it
  would also cache TMDB *API* responses — the detail screen's Refresh button must
  never be answered out of a cache we introduced. Stale availability is the one
  thing that button exists to prevent.
- `RemoteImagePhase` is a top-level type, not nested in `RemoteImage<Content>`.
  It has to be: the content closure is what Swift infers `Content` *from*, so a
  nested `RemoteImage<Content>.Phase` is circular and won't compile. This is the
  same reason Apple made `AsyncImagePhase` top-level.
- The poster cache is keyed by URL and the request policy is
  `returnCacheDataElseLoad`, which is safe because a TMDB image path is immutable —
  new artwork is published at a *new* path. This is also what makes a relaunch
  paint the library instantly, and what lets it paint at all with no signal.
- 8 new tests (45 total) pin the behaviour that *is* the bug: a poster that fails
  once still loads, a 404 isn't retried, a cancelled cell isn't a failure, and a
  poster is fetched once and then served from memory. `StubTransport` (a
  `URLProtocol`) scripts the answers; the suite is `.serialized` because that
  script is shared static state.
- Verified on the Simulator with the `-seed-sample-library` scaffold from Fix 1
  (kept out of the committed diff, as before) — real posters render in both grid
  tabs. **The intermittent failure itself can't be reproduced on demand**, so the
  retry/cache guarantees are pinned by the unit tests rather than by a screenshot.
- Fixes Search's grid too, since `MediaPosterView` is shared.

## Backlog
- **The detail page's backdrop and provider logos still use bare `AsyncImage`.**
  Same latent weakness as Fix 2 — no cache, no retry — but a much milder symptom
  (a flat rectangle behind the header, or a blank provider tile), and they weren't
  what was reported. Moving them to `RemoteImage` is a small, obvious follow-up.

New bugs and enhancements get appended here as they're reported, then promoted to
**Fixed** with their branch and commit once merged.
