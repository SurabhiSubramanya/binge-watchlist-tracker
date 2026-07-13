# Binge

A personal iPhone app for tracking movies and TV shows you *want to watch* and
have *already watched*. Each title is one entry — no episodes, no ratings — with
its poster, its release date, and where you can stream it.

Search TMDB, add a title to **Want to Watch** or **Watched**, and Binge keeps the
artwork, release date, genres and streaming providers for it. Anything not out
yet can set a reminder that fires on the morning of release day.

- **SwiftUI + SwiftData**, on-device only. No account, no server, no iCloud sync.
- **No third-party dependencies.** Nothing to install; it builds straight from a
  clean checkout.
- **Metadata from [TMDB](https://www.themoviedb.org)**, using a free token you
  paste into Settings — no secrets are committed to this repo.

## What you need

| | |
|---|---|
| **Xcode** | 16 or later (built and run on **26.6**). Free from the Mac App Store. |
| **iPhone** | iOS 17.0 or later — SwiftData needs it. Or just use the Simulator. |
| **Apple ID** | Any free one. A paid Developer account is *not* required. |
| **TMDB account** | Free. See below. |

The first launch of Xcode after install will ask to install additional
components — let it finish before building.

## 1. Get a TMDB token

Binge talks to TMDB for search, artwork, release dates, and streaming
availability. It needs your own free token.

1. Create an account at [themoviedb.org](https://www.themoviedb.org/signup).
2. Go to **Settings ▸ API** ([direct link](https://www.themoviedb.org/settings/api))
   and request an API key. Personal / educational use is accepted; the form takes
   about a minute.
3. Copy the **API Read Access Token**.

> [!IMPORTANT]
> Copy the **long** token — the v4 *Read Access Token*, a JWT starting with
> `eyJ…` and hundreds of characters long. **Not** the short 32-character v3
> *API Key*. Binge sends it as `Authorization: Bearer <token>`; the v3 key will
> fail with a 401 on every request.

You'll paste it into the app on first launch (step 3), not into a file here.

## 2. Build and run

### On the Simulator

Open `Binge.xcodeproj` in Xcode, pick any iPhone simulator, and press **⌘R**.
That's it — no signing setup needed for the Simulator.

From the command line:

```sh
xcodebuild -project Binge.xcodeproj -scheme Binge \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```

<details>
<summary>If <code>xcodebuild</code> can't find the SDK</summary>

`xcode-select -p` may still point at the Command Line Tools rather than Xcode.
Either repoint it (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the command.
</details>

### On your iPhone, with a free Apple ID

This works on a free Apple ID with one caveat, covered at the end.

1. **Add your Apple ID to Xcode** — *Xcode ▸ Settings ▸ Accounts ▸ +*.
2. **Select your team** — open the project, go to the **Binge** target ▸
   *Signing & Capabilities*, keep **Automatically manage signing** checked, and
   pick your **Personal Team** in the *Team* dropdown.

   > The repo currently commits `DEVELOPMENT_TEAM = 97892S7UQ8` (the owner's
   > personal team). If you're anyone else, this step replaces it with yours.

   Xcode may report that the bundle id `com.binge.Binge` is unavailable — change
   it to something unique (e.g. `com.yourname.Binge`) and it'll sign fine.
3. **Enable Developer Mode on the iPhone** — *Settings ▸ Privacy & Security ▸
   Developer Mode*, toggle on, and let it restart. The device won't accept
   builds without this.
4. **Plug in / pair the phone**, select it as the run destination, and press **⌘R**.
5. **Trust the developer profile on the phone.** The first launch will refuse
   with an untrusted-developer alert. Go to *Settings ▸ General ▸ VPN & Device
   Management*, tap your Apple ID, and **Trust**. Then launch the app again.

Once the team is set, device builds run headlessly from the CLI too:

```sh
# find the device's UDID
xcrun devicectl list devices

xcodebuild -project Binge.xcodeproj -scheme Binge \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -configuration Debug -allowProvisioningUpdates build

xcrun devicectl device install app --device <DEVICE_UDID> \
  <DERIVED_DATA>/Build/Products/Debug-iphoneos/Binge.app
xcrun devicectl device process launch --device <DEVICE_UDID> com.binge.Binge
```

> [!WARNING]
> **Free signing expires after ~7 days.** This is an Apple limitation of free
> Apple IDs, not a bug in the app. After a week the app stops opening and must be
> rebuilt and reinstalled. Your library and token survive — reinstalling over the
> top keeps both. (A paid Developer account extends this to a year.)

## 3. First launch

The app opens **on the Settings tab** with a badge, because there's no token yet.

1. **Paste your TMDB token** and tap *Save token*. It goes into the iOS Keychain —
   never plain text, never off the device. Once saved it's shown masked (`••••1234`).
2. **Check the streaming region.** It defaults to your device's region and is what
   provider lookups are made against — streaming availability is country-specific.
   Change it here if it's wrong.
3. **Notifications:** Binge does *not* ask for permission at launch. The prompt
   appears the first time you flip a reminder toggle on a title's detail screen.
   If you denied it earlier, the detail screen says so and points you to the
   Settings app.

## 4. Manual test checklist

A quick pass that exercises everything, once per device:

- [ ] **Token** — Settings, paste token, save. The badge on the tab clears.
- [ ] **Search** — Search tab, type a well-known title (e.g. *Dune*). Results
      appear as posters after a short pause (queries are debounced by 350ms).
- [ ] **Add** — add one to *Want to Watch* and one straight to *Watched*. Both
      show an **In Library** badge in search results afterwards.
- [ ] **Library** — Library tab. Each title is under the right segment, with its
      poster and year. Try the sort menu (*Recently added* / *Release date* /
      *Title*) and the *All* · *Movies* · *TV* filter.
- [ ] **Detail** — tap a poster. Backdrop, title, release date, genres, overview,
      and **Where to watch** all load. A title that streams nowhere in your region
      says so explicitly rather than showing a blank.
- [ ] **Move & remove** — *Mark as Watched* moves it between segments. *Remove
      from Library* asks first, then deletes it.
- [ ] **Reminder** — open an **unreleased** title (the toggle only appears for
      Want-to-Watch titles with a future date). Flip *Remind me when it's out* and
      accept the notification prompt. It schedules for 9am on release day.
- [ ] **Cold relaunch** — quit and reopen. Library and token are still there.

Run the unit tests (37, Swift Testing) with:

```sh
xcodebuild -project Binge.xcodeproj -scheme Binge \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

They cover the pieces with real logic: the TMDB decoders, library sort/filter,
and — most of all — release-date and reminder correctness.

## Gotchas

**Deleting the app wipes your TMDB token, not just your library.** Since iOS 10.3
removing an app removes its Keychain items too. To update the app, *reinstall over
the top* — don't delete first, or you'll be pasting the token in again.

**Release dates are calendar days, not moments in time.** TMDB publishes
`"2024-02-27"` — no time, no time zone. Binge stores dates as **UTC midnight** and
always reads them back through a UTC calendar (`Support/ReleaseDate.swift`), so a
title shows the day TMDB published in every time zone. Reminders use a
time-zone-free `DateComponents` trigger, so they fire at 9am wherever *you* are.
Anything touching `releaseDate` must go through `ReleaseDate` — never
`Calendar.current` directly, which reads the day back as the *previous* one
anywhere west of Greenwich.

**`devicectl` says `connected (no DDI)`.** Developer Mode is off on the iPhone —
see step 3 above.

**Streaming data is TMDB's (via JustWatch) and is region-specific.** An empty
"Where to watch" is usually a real answer, not a failure.

## Project layout

```
Binge/
  BingeApp.swift          app entry: ModelContainer + AppSettings injection
  Models/MediaItem.swift  the SwiftData model — one row per title
  Services/               TMDBService + models, NotificationManager, ReleaseReminder
  Support/                AppSettings, Keychain, ReleaseDate, Theme, SampleLibrary
  Views/                  ContentView (tabs), Library, Search, MediaDetail,
                          Settings, MediaPosterView
BingeTests/               Swift Testing suites (decoding, sort/filter, dates, reminders)
docs/plans/               the build plan, and the running fixes/enhancements log
```

The Xcode project uses a file-system-synchronized group: new files under `Binge/`
are picked up automatically, with no `.pbxproj` editing.

---

This product uses the TMDB API but is not endorsed or certified by TMDB.
