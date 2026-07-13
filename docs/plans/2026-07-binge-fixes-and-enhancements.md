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

## Backlog
Nothing queued yet. New bugs and enhancements get appended here as they're
reported, then promoted to **Fixed** with their branch and commit once merged.
