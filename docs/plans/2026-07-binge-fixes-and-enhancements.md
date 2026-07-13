# Binge — fixes & enhancements

Companion to [`2026-07-binge-app.md`](2026-07-binge-app.md), which covers the ten
subtasks that built the app. That plan is closed once Subtask 10 (docs) lands;
**everything after feature-complete lives here** — bugs found in real use, and
functionality added beyond the original scope.

## Workflow
One bug or change at a time, each on its own branch off `main` — `fix/NN-name` for
a bug, `feat/NN-name` for an enhancement, sharing **one** number sequence so the
order is legible at a glance. Built and run before review, fast-forward merged once
approved. Same rhythm as the subtasks — no batching, even for small related fixes.

Bookkeeping (marking an entry below merged) lands as its own commit on `main`, *not*
in the next branch — otherwise Fix N's paperwork ends up in Fix N+1's diff.

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

### Fix 2 — Posters sometimes don't load in the library grid ✅
*Fixed 2026-07-12 · commit `1c8062b` · branch `fix/02-poster-loading` · merged to `main`*

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

### Fix 3 — Blank white screen at launch, then the app snaps in ✅
*Fixed 2026-07-12 · commit `a6d8bb5` · branch `fix/03-launch-screen` · merged to `main`*

**Symptom.** Launching Binge showed a blank **white** screen, which then jumped
straight to the app with nothing in between. No app name, no branding, and a white
flash in front of an app that is otherwise entirely dark.

**Cause.** Two separate things, which is why it looked worse than either.

*The white.* The project asked for a launch screen through Xcode's generated
`Info.plist` keys — `INFOPLIST_KEY_UILaunchScreen_Generation = YES` plus
`INFOPLIST_KEY_UILaunchScreen_UIColorName = LaunchBackground`. Those two do not
compose. What Xcode actually generated was a **nested, empty** dictionary:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UILaunchScreen</key>   <!-- nested -->
    <dict/>                     <!-- and empty: UIColorName never made it in -->
</dict>
```

A `UILaunchScreen` with no `UIColorName` means "launch screen, default styling" —
and the default is white. The dark `#0B0D13` was configured, compiled into the asset
catalog, and never once read. `Theme.swift` even carried a comment saying
`bingeGround` "shares the asset the launch screen uses so the hand-off doesn't flash
a different shade". That was aspirational: the launch screen had never used it.

*The snap.* A launch screen is a **still image**. It cannot animate, and iOS tears it
down the instant the first app frame is ready. Even once it was the right colour,
there would still be a hard cut from a static image to a live UI.

**Fix.**
- **`LaunchScreen.storyboard`**, wired up with `INFOPLIST_KEY_UILaunchStoryboardName`.
  A storyboard rather than the plist dictionary because that dictionary can only
  place a colour and an image — it cannot render *text*, and the app name was the
  requirement. Dark ground, "Binge" in 46pt bold, a 44×3 amber rule beneath it.
- **`LaunchCurtain`**, a SwiftUI view that redraws that same wordmark *pixel for
  pixel* and then animates away: the rule widens 44→132, the wordmark eases up 4%,
  and the whole thing cross-fades into the app. Because its first frame is identical
  to the storyboard, the hand-off is invisible — the user sees one continuous screen
  that lifts, not two screens swapped. Under a second, start to finish.

**Notes worth keeping:**
- **`UILaunchScreen` had to be deleted, not just left alone.** On iOS 14+ it takes
  *precedence* over `UILaunchStoryboardName`, so leaving that empty dictionary in
  place would have kept the white screen no matter how good the storyboard was.
  Both build configs (Debug *and* Release) were carrying it.
- **The storyboard and `LaunchCurtain` are a matched pair.** 46pt bold, 44×3 rule,
  16pt apart, centred — the numbers appear in both files and must stay in sync, or
  the app visibly jumps at the exact moment it launches. Both files say so.
- The rule is a plain `Rectangle`, not a `Capsule`, purely so it matches the
  storyboard: a launch screen can't round a corner without runtime attributes, and
  iOS doesn't apply those when rendering one.
- `ContentView` is alive *underneath* the curtain from the first frame, so its `task`
  (reconciling reminders, choosing the opening tab) runs while the curtain is still
  up. Lifting it reveals a settled screen rather than one still assembling itself.
- Reduce Motion gets no flourish and barely a pause — someone who asked the system
  for less movement is not asking to look at a splash for longer.
- Verified on the Simulator by capturing frames across a cold launch after a fresh
  install (an uninstall also clears iOS's cached launch snapshot, which otherwise
  survives and will happily keep showing you the old one).
- **The empty space above the wordmark is deliberate** — it's the slot for the app
  icon, which is the next change.

### Change 4 — Watched counts under the Library grid ✅
*Added 2026-07-12 · commit `2c15038` · branch `feat/04-watched-counts` · merged to `main`*

**Ask.** Show how many movies and how many TV shows are in the library, at the bottom
of the Library page. **Watched only** — not Want to Watch.

**What shipped.** A `LibraryFooter` pinned beneath the grid: two big amber numbers
over small-caps `MOVIES` / `TV SHOWS` labels, split by a hairline. Pinned rather than
scrolled with the grid — a total that scrolls off the bottom is a total you have to go
hunting for, which rather defeats it. Hidden entirely on Want to Watch, and hidden when
nothing has been watched yet (a pair of zeroes is not a fact worth a bar of chrome).

**Two decisions the user made, not me:**
1. **The design.** Three treatments were built and screenshotted *in the running app*
   (minimal grey text / icon chips / the stats bar) rather than mocked. ASCII previews
   in the question tool were rejected, rightly — you cannot judge this from a drawing
   of it. The stats bar won. **Re-do this trick for any visual choice**: build the
   variants behind a launch argument, screenshot each, delete the losers.
2. **How it interacts with the type filter.** The Library already filters by All /
   Movies / TV, so "when the filter is on Movies, does the TV count vanish?" had to be
   settled. Chosen: **the totals never move.** The tally is a fact about the library,
   not a description of the grid. The consequence is accepted and deliberate — with the
   filter on Movies you will see a TV count above a grid containing no TV.

**Notes worth keeping:**
- `LibraryView.Tally` is a nested struct, not a computed property in the body, purely so
  it can be tested without driving a view. It takes the **whole** `items` array —
  passing `visibleItems` is the one change that would quietly break decision (2), so
  `Tally.init` says so in a comment.
- **That comment is the guard, not a test.** A unit test can't check which array the
  *view* passes in without driving the view, so `LibraryTallyTests` pins the next best
  thing: that a filtered input visibly changes the answer. An earlier version of that
  test asserted `Tally(items) == Tally(items)`, which is a tautology and could never
  have failed — it was cut.
- **Pluralisation is manual.** The number is styled separately from its label (amber,
  larger), so it can't carry SwiftUI's automatic grammar agreement with it — the label
  has to agree on its own, or a library with one film reads **"1 MOVIES"**. Verified on
  the Simulator: it reads "1 MOVIE / 1 TV SHOW".
- 5 new tests (50 total).

### Fix 5 — Detail-screen action rows render as fat tinted pills ✅
*Fixed 2026-07-12 · commit `3174973` · branch `fix/05-detail-action-rows` · merged to `main`*

**Symptom.** On the physical iPhone, "Mark as Watched" and "Remove from Library" each
sat inside a big filled olive capsule with an oversized icon, and *both* were amber —
so deleting a title looked exactly like marking it watched. On the Simulator the same
build looked completely fine, which is what made it interesting.

**Cause.** The user has **Button Shapes** switched on (Settings → Accessibility →
Display & Text Size → Button Shapes). With it on, iOS draws a filled shape behind every
system-styled `Button` and paints it with the ambient tint — here `.accentColor`, set on
the `TabView` in `ContentView` and inherited all the way down. That single setting
produced all three complaints at once: the pill, the inflated icon, and the loss of the
destructive red (the accent tint wins over the `.destructive` role).

The rows were `Label`s inside default-styled `Button`s, i.e. they were asking the system
to decorate them. The system obliged.

**Fix.** Draw them as what they actually are — *list rows*, the same thing Settings
shows — and stop leaving anything to the system to decorate:
- `.buttonStyle(.plain)` on both, so no system button chrome is drawn at all.
- An explicit `actionRow`: icon in a **fixed 24pt column** (so a trash can and a tick
  start their titles at the same x), `.font(.body)` so it still honours Dynamic Type,
  and `.contentShape(Rectangle())` so the whole row is the tap target rather than just
  the text.
- Explicit `.red` on Remove, so the destructive colour can't be tinted away.
- Inset separators, aligned to the titles like a system list.

**Notes worth keeping:**
- **It only reproduces with Button Shapes on**, which is why it was invisible on the
  Simulator. `simctl ui` can't toggle it — but
  `simctl spawn <udid> defaults write com.apple.Accessibility ButtonShapesEnabled -bool YES`
  can, and that reproduced the bug pixel for pixel. **Verified both ways**: the screen
  now renders identically with the setting on *and* off. Re-use this trick for any
  "looks wrong on the phone, fine on the Simulator" report — the difference is usually
  an accessibility setting, not the hardware.
- **The first scaffold lied.** Opening `MediaDetailView` directly, outside `ContentView`,
  dropped the `.tint(.accentColor)` that the real app inherits from the `TabView` — so
  Remove came out red and the bug half-vanished. A scaffold has to reproduce the *ambient
  environment*, not just the screen. The `.tint` was added to it before trusting anything
  it showed.
- Not defeating the accessibility setting, just declining to be decorated by it: the rows
  live in a grouped card with separators and read as tappable rows the way Settings' do.

## Backlog
- **App icon / logo, and reuse it on the launch screen.** Deferred by the user. Binge
  currently ships the empty `AppIcon` placeholder, so the Home Screen shows a blank
  white tile. Once there's a logo it drops into the gap above the wordmark in both
  `LaunchScreen.storyboard` and `LaunchCurtain`.
- **The detail page's backdrop and provider logos still use bare `AsyncImage`.**
  Same latent weakness as Fix 2 — no cache, no retry — but a much milder symptom
  (a flat rectangle behind the header, or a blank provider tile), and they weren't
  what was reported. Moving them to `RemoteImage` is a small, obvious follow-up.

New bugs and enhancements get appended here as they're reported, then promoted to
**Fixed** with their branch and commit once merged.
