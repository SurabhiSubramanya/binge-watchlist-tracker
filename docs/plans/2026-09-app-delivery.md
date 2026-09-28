# Binge — app delivery framework

How to get Binge onto other people's phones (as a normal home-screen app), and the
trade-offs between the routes. Written 2026-09-27 while weighing public App Store vs
TestFlight vs Ad Hoc. Companion to
[`2026-07-binge-fixes-and-enhancements.md`](2026-07-binge-fixes-and-enhancements.md)
(where the original "TestFlight" backlog item lived) and to `binge-build-run` (the
device build/install commands this reuses).

> **Status: decision pending.** No delivery work started. The paid Apple Developer
> Program is already in place (Ops 9, Team `97892S7UQ8`), so the account gate is done;
> what remains is choosing a route and, for anything shared with non-technical people,
> the **TMDB-key rework** (see Q1). This doc is the reference to decide from.

## Context

Binge is a personal SwiftUI/SwiftData watch-tracker, currently distributed only as a
**development sideload** to the owner's iPhone 13 Pro (~1-year signing since the paid
membership — expires 2027-07-17). The goal now: let other people (and/or the public)
**see the app icon and open it like any normal app**. Every route below achieves that
— the app always installs as its own home-screen app; the delivery mechanism
(TestFlight, Ad Hoc link, App Store) is just how the bytes get there, not a container
the app runs inside.

## Answers to the key questions

**Q1 — Do recipients need their own TMDB token?**
**As the app is built today, yes.** Binge does nothing until the user pastes a TMDB v4
Read Access Token into Settings (stored in the Keychain). A recipient would face that
same empty Settings screen and would have to create a TMDB account and generate a
token — fine for the developer, a dealbreaker for anyone else. **The fix is to embed
your own TMDB key in the app** so nobody has to paste anything. At small scale
(TestFlight/Ad Hoc to family) a key baked into the app is acceptable; only a *public*
release really warrants a backend proxy (a key inside a widely-distributed binary can
be extracted and abused, and TMDB would rate-limit/revoke it). So: this is a small,
contained code change, and it's a prerequisite for sharing with non-technical people
on **any** route. Sharing only with yourself/technical people → you can keep the
paste-token model.

**Q2 — Does the periodic refresh delete the recipient's library?**
**No.** Refreshing a build (TestFlight's 90-day cycle, or Ad Hoc's ~yearly re-sign) is
an **install-over-the-top** — exactly what was done verifying the season-tracking
migration: the SwiftData store and Keychain survive because the app identity (bundle
id `com.binge.Binge` + team `97892S7UQ8`) is unchanged. Expiry never *deletes* data;
an expired build simply **won't launch** until the recipient installs the refreshed
one, and their data is all still there when they do. **Only deleting the app wipes the
library** (and, per the standing gotcha, the Keychain token with it).

**Q3 — Can the refresh be automated so it's not manual when nothing changed?**
**Partly, and it differs by route:**
- **TestFlight (90-day):** you can't extend an existing build's expiry — a *new* build
  must be uploaded (bump the build number even with identical code). That upload is
  fully scriptable/schedulable (GitHub Actions or local `launchd`/cron every ~80 days,
  uploading via an **App Store Connect API key** — headless, no interactive login),
  with TestFlight set to auto-distribute to a tester group. What can't be removed:
  external builds get a quick **Beta App Review** each time, and testers tap "Update"
  in TestFlight (or auto-update if enabled). So: hands-off for you, but the treadmill
  still turns.
- **Ad Hoc (~yearly):** same idea, a longer clock — re-archive + re-sign once a year
  and redistribute. Automatable the same way; no review involved. See below.
- **Public App Store:** **no expiry at all** — you only ship a new build when *you*
  choose to. This is the only route with zero recurring-refresh obligation, at the
  cost of the token rework + full App Review.

## The three routes at a glance

| | Refresh cadence | Who can install | UDIDs? | Review | Token rework | Effort |
|---|---|---|---|---|---|---|
| **Ad Hoc** | ~1 year (re-sign) | ≤100 devices you register | **yes, per device** | none | needed for non-technical | medium |
| **TestFlight** | every 90 days (automatable) | anyone invited (≤10k) | no | light Beta review | needed for non-technical | medium |
| **Public App Store** | never expires | the general public (searchable) | no | full App Review | needed + proxy advised | high |

If the priority is **"set it and forget it" for a handful of known people**, Ad Hoc's
yearly clock beats TestFlight's 90-day one. If it's **"anyone can find it, never think
about refresh again,"** only the public App Store delivers that.

## Ad Hoc — in detail

**What it is.** A distribution method (paid program only — ✓ have it) that installs a
signed build onto a **fixed set of devices you register by UDID**, outside the App
Store and TestFlight. No App Review, no 90-day expiry.

**Requirements**
- **Paid membership** — done (Team `97892S7UQ8`).
- **Each recipient device's UDID registered** in the Developer portal
  (Certificates, Identifiers & Profiles → Devices). Cap: **100 iPhones per membership
  year** (the list can be reset once a year).
- An **Apple Distribution certificate** + an **Ad Hoc provisioning profile** embedding
  those UDIDs. Note this is a *different* signing identity than the current sideload,
  which uses an **Apple Development** cert (`Apple Development: …(7VQFURL6DT)`).
  Automatic signing (`-allowProvisioningUpdates`) can create both.
- Validity: distribution cert + Ad Hoc profile last **~1 year** — same cadence as the
  current sideload (and the reason yearly is the natural refresh beat).

**How a recipient installs it — two ways**
1. **Over-the-air (no cable).** Host the exported `.ipa` **plus a `manifest.plist`** on
   an **HTTPS** server, then share an
   `itms-services://?action=download-manifest&url=https://…/manifest.plist` link. They
   open it in Safari and confirm. Works only if their UDID is in the profile (else iOS
   refuses to install). The HTTPS host can be anything static — a small bucket, GitHub
   Pages, etc.
2. **Wired.** Install the `.ipa` via Finder / Apple Configurator / `devicectl` (what
   we already do for the owner's phone). Fine for people physically near you; not for
   remote family.

**The friction that makes Ad Hoc worse than TestFlight for non-technical people:** you
must **collect each person's UDID** (they find it via Finder/Apple Configurator or a
UDID-profile website and send it to you), register it, and re-export a profile that
includes it. Adding a new person later means editing the profile and re-exporting.
TestFlight needs none of that — just an email/link.

**The friction that makes it *better*:** no App Review, no 90-day clock — a build lasts
~a year, matching signing, so it's genuinely "install once, refresh annually."

## Implementation subtasks (if Ad Hoc is chosen)

Executed one at a time, each on its own branch off `main`, same workflow as always.

### 1. Embed the TMDB key + retire the paste-token requirement *(only if sharing beyond yourself/technical users)*
Bake a TMDB v4 token into the app (e.g. an `xcconfig`/build setting read at runtime,
kept out of git) as the default, so `AppSettings.bearerToken` falls back to it when the
Keychain has none. Decide whether to **hide the Settings token field** entirely or keep
it as an optional override. Preserve the existing precedence rule (a user-entered token
still wins if kept). Confirm the app is fully usable on a fresh install with no manual
token step.
- **Model:** Sonnet 5 — contained change across `AppSettings`/`Keychain`/`SettingsView`
  following existing patterns, but it touches the app's core config path and a secret,
  so it wants care (and a decision on hide-vs-override).
- **Depends on:** none. *Skip entirely if Ad Hoc is owner-only.*

### 2. Collect + register recipient device UDIDs *(ops, no code)*
Gather each device's UDID, add them under Devices in the Developer portal. One-time per
device; repeat when adding someone.
- **Model:** n/a (manual web + coordination step).
- **Depends on:** none.

### 3. Ad Hoc archive + export pipeline
Add an `exportOptions-adhoc.plist` (`method: ad-hoc` / newer Xcode `release-testing`,
`teamID: 97892S7UQ8`, automatic signing). Script:
`xcodebuild -scheme Binge -destination 'generic/platform=iOS' -archivePath build/Binge.xcarchive archive`
then
`xcodebuild -exportArchive -archivePath build/Binge.xcarchive -exportOptionsPlist exportOptions-adhoc.plist -exportPath build/adhoc -allowProvisioningUpdates`,
producing `Binge.ipa`. Verify the profile's embedded UDIDs with
`security cms -D -i` on the archive's profile (the Ops 9 trick).
- **Model:** Sonnet 5 — build-config + signing plumbing, fiddly but well-trodden.
- **Depends on:** 2 (profile must include the UDIDs).

### 4. Over-the-air distribution *(ops / small template)*
Write the `manifest.plist` template (bundle id, version, title, HTTPS `.ipa` URL), pick
an HTTPS host, and produce the `itms-services://` link. Document the recipient steps.
- **Model:** Haiku 4.5 — templated plist + hosting, no real logic.
- **Depends on:** 3.

### 5. Yearly refresh runbook *(docs)*
A short runbook: bump build number, re-run subtask 3's archive/export (re-signs against
a fresh ~1-year profile), re-host, notify recipients to reinstall over the top (data
preserved per Q2). Optionally wire the archive+export+publish into CI on an ~11-month
schedule so it's hands-off.
- **Model:** Haiku 4.5 — documentation + optional CI YAML.
- **Depends on:** 3, 4.

## Risks & edge cases
- **Signing-identity switch.** Moving from the current **Development**-signed sideload to
  an **Ad Hoc (Distribution)**-signed build keeps the same bundle id + team, so it should
  update in place and preserve data — but verify on the owner's phone first (back up the
  container à la the season-tracking migration before the first Ad Hoc install, just in
  case entitlements differences force a reinstall).
- **UDID cap & churn.** 100 devices/year, and the list only fully resets annually —
  don't burn slots casually.
- **Embedded key exposure.** A key in the `.ipa` can be extracted. Acceptable for a
  small trusted group; if the recipient list grows or leaks, rotate the key (and prefer
  a proxy before any public move).
- **OTA hosting must be HTTPS** with a valid cert, or `itms-services` install silently
  fails.
- **Lapsed profile = app won't launch** until re-signed/reinstalled (data intact) — the
  yearly beat is not optional.

## Recommendation
- **Just you / a couple known devices, minimal fuss:** **Ad Hoc** (or even the current
  ~1-year sideload) — yearly refresh, no review, no 90-day clock. Do subtask 1 only if a
  non-technical person is on the list.
- **A wider invite list without collecting UDIDs:** **TestFlight** — accept the 90-day
  cycle (automate the upload).
- **Truly public, no refresh obligation:** **public App Store** — commit to the token
  rework + review (its own future plan).

## Open questions
1. **Who's the audience** — just you, a known handful, an invite list, or the public?
   (Picks the route.)
2. **Are any recipients non-technical?** If yes, subtask 1 (embed key) is required
   regardless of route.
