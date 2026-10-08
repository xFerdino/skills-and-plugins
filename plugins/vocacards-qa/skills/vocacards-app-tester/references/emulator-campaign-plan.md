# Emulator campaign plan (mode G)

A campaign plan for Android Studio emulators. It's for three things:
- **finishing rows a physical non-rooted phone can't run**
- **verifying fixes** that landed since the last device campaign
- **regressing redesigned surfaces** across a matrix (API level, screen size, font scale,
  theme, style, RTL, TalkBack)

It uses the same ledger, statuses, definition of done and evidence rules as
`full-device-test-plan.md` §1, and the emulator mechanics in `device-testing.md` §10d.
Read both first.

**What emulators are not for:** performance. Mark every PF row `N/A(emulator; measure on
the physical phone)`. MIUI-specific behaviour is also out of scope here; that's the
physical Redmi's job.

## 1. Setup facts (measured 2026-10-06, re-check each run)

- **SDK:** `C:\Users\Luk\AppData\Local\Android\Sdk`, with `emulator\emulator.exe`. WHPX
  acceleration is usable (`emulator -accel-check`). There are no `cmdline-tools`, so no
  `sdkmanager`.
- **Installed images:** only `android-36.1 / google_apis_playstore / x86_64`, a Play image
  that isn't rootable. Get Google APIs images through Android Studio's SDK Manager, or
  install Google's `cmdline-tools` from `dl.google.com` and run
  `sdkmanager "system-images;android-<N>;google_apis;x86_64"`.
- **Other sessions' AVDs exist** (`Medium_Phone_API_36.1`, `vocacards_auth_test`,
  `vc_anki_*`). **Never use or modify an AVD you didn't create.** Name yours
  `qa-emu-<date>-<role>`, and before every adb command check its serial with
  `adb -s <serial> emu avd name`.

## 2. The AVD set

| Role | Image | Used for |
|---|---|---|
| `play` | API 36.x Google **Play** | billing (P rows), Play-installed release build, TalkBack (Android Accessibility Suite from Play) |
| `root` | API 35/36 **Google APIs** | `adb root`: the release build's DB oracle, `date -s` time travel, unrestricted `/data/local/tmp` |
| `api29` | API 29 Google APIs | oldest-supported behaviour: notifications before the API 33 runtime permission, scoped storage, the back gesture |
| `small` | API 34/36 Google APIs, a small-screen profile (about 5.0", ≤ 1080×1920) | layout at small sizes with the largest font scale |
| second `root` or `play` | as needed | two-device sync and slots (AC4–AC6) |

After each AVD is set up (app installed, signed in, fixtures imported), save a
`qa-base` snapshot (`adb emu avd snapshot save qa-base`). Load it
(`adb emu avd snapshot load qa-base`) before every row that needs a known baseline.
Record the snapshot name in the row, and keep a `snapshots.md`: AVD → snapshot → the state
it holds.

## 3. Builds

- **Dev client (`cards.voca.app.dev`):** build it from your own fresh checkout
  (`C:\tmp\vc-emu-<date>`: `git clone --no-hardlinks`, `npm ci --offline`, `.env.local`
  with `APP_VARIANT=development`, `expo prebuild` with that variable set). Check the
  generated manifest's package and schemes before building (device-testing §11). Serve
  Metro from that tree on its own port.
- **Release (`cards.voca.app`):**
  - *Play AVD:* install from the Play Store under the test Google account. The **owner**
    signs that account in on the emulator. Never type credentials.
  - *Root AVD:* build a local release APK (debug-signed, per `docs/android-build.md`) and
    `adb install` it. This is the only way to get a **release-build DB oracle**:
    `adb root`, then pull `/data/data/cards.voca.app/files/SQLite/vocacards.db` plus its
    `-wal` byte-exact.
- Record the SHA and versionCode for every build, on every row.

## 4. Catalog

Build `STATE.md` from these groups. IDs that exist in `full-device-test-plan.md` keep their
meaning; add a `@<avd>` suffix when a row runs on several AVDs.

### EA — Rows a non-rooted phone couldn't run (root AVD unless noted)

| ID | Test | Pass when |
|---|---|---|
| EA1 | Re-run the release-build rows with a DB oracle: L3, F3, B2, ST1–ST3 | each passes with a DB before/after, not just UI |
| EA2 | TT1–TT5 with `date -s` AND through the Settings route | as in the full plan; automatic time restored and read back |
| EA3 | N2/N3 across a moved clock | the reminder fires at the moved time; tap opens the Flow |
| EA4 | X9 system dark/light, X10 force-RTL plus an Arabic locale | per design; no mirrored-layout breakage |
| EA5 | AC4–AC6 on two emulators, same test account | the change arrives; latency recorded; slot behaviour per DECISIONS Suite 3 |
| EA6 | B10 and AM14 kill loops from a `qa-base` snapshot | baseline or full, never partial; a mid-transaction kill evidenced |
| EA7 | FI1–FI4 fresh install from a clean snapshot | onboarding completes; empty states and the import entry are correct |
| EA8 | Large import (≥ 20k cards, ≥ 5k media) | no "database is locked"; time and memory noted (not as perf verdicts) |

### EF — Fix verification

For every fix commit since the previous campaign report, write one row. Read
`git log --since=<last report date> origin/master` and keep the commits that claim to fix
a ledger finding. Then:
- **Re-run the original row** on current master: on the dev client, and on the release
  build where relevant.
- **Status:** `FIXED-VERIFIED(<build>)` or `STILL-BROKEN(<build>)`, with evidence.
- **Accessibility fixes:** verify with TalkBack actually driving the control, plus
  `uiautomator dump --compressed` with a control run. A dump alone isn't TalkBack
  evidence.

### ER — Redesign regression

For every surface a recent redesign touched (read the log and the touched files), one
row per surface. **The checks are risk-sampled, not exhaustive.** A full 16-combination ×
3-font × RTL × TalkBack × offline matrix per surface runs to thousands of captures; the
2026-10-08 campaign closed 30 of 161 rows in two days against it. Every category is still
checked on every surface, but each combination is checked only where a change could
plausibly break it.

**Base pass: every surface, always.**
1. **Function:** the main actions work, with a DB oracle where data changes.
2. **Offline:** clear behaviour, no blank screen.
3. **TalkBack:** labels, roles, focus order and states, driven with real TalkBack on one
   build. Add a `uiautomator dump --compressed` with a control run.
4. **One visual capture:** the default theme and style, at the **maximum font on the
   `small` AVD**. That's the combination most likely to clip.

**Escalations: add these only when the trigger applies,** and record the trigger in the
row:

| Check | Trigger: run it if the diff for this surface… | Scope when triggered |
|---|---|---|
| All 4 themes × 4 styles | changes colour, tokens, `tint`/`accent`, pills or chips, borders or backgrounds, OR typography, faces or `designStyles` scales | all 16, with the Noir chrome audit |
| Themes only (4) | changes colour or tokens but not typography | the 4 themes in the default style |
| Styles only (4) | changes typography or spacing but not colour | the 4 styles in the default theme, at max font |
| Font 1.0 / 1.3 | the max-font capture shows tight fit (text within 4 dp of a container edge) or uses a fixed-size box | add the two lower scales |
| RTL | the surface has directional layout: rows with leading or trailing elements, chevrons, swipe directions, `left`/`right`/`start`/`end` in its styles | force RTL plus an Arabic locale |
| Both builds | the diff touches native config, R8-sensitive code (reflection, dynamic requires), or anything a dev-only path guards | the same checks on release and dev |

**Not sampled: always exhaustive.** The Flow card faces (the frozen geometry; any change
is high-risk), the paywall, and destructive dialogs (delete account, delete deck, restore)
get the full 16 combinations × 3 fonts. A wrong colour or a clipped warning there costs
money or data.

A surface fails a row if the base pass or any triggered escalation fails; name which.
Record the escalations **not** triggered, with the reason (for example "styles: no
typography change in `abc123`"). An untriggered check is a reasoned scope decision, not a
skip.

**R8 / minification row:** when a release build turns on R8, exercise import, backup,
restore, sign-in, the paywall and reminders on the release build, with `logcat -b crash`
running. R8 can strip code that's reached only by reflection, so a crash there is 🔴.

### EM — Matrix differences

| ID | Test | Pass when |
|---|---|---|
| EM1 | Notification permission flow on API 29 vs API 33+ | no runtime prompt below 33; a prompt, denial handling and the blocked notice at 33+ |
| EM2 | File picker and scoped storage on API 29 vs 36 | import and export work on both |
| EM3 | Back gesture vs the 3-button nav on API 29 | the discard guard and sheets close correctly in both modes |
| EM4 | Small screen at the largest font: Flow, Add, Settings, the paywall, onboarding | nothing off-screen or unreachable |

## 5. Order

Setup (AVDs, builds, `qa-base` snapshots) → EF (fix verification, highest value) → EA →
ER → EM → K verdicts → cleanup. At cleanup:
- Stop the emulators and Metro.
- **Keep** your AVDs and snapshots for reuse, and list them in the report.
- Delete only your own `C:\tmp\vc-emu-*` checkouts, after `cmd /c dir /AL /S /B` prints
  nothing.
- Never touch anyone else's AVD.

## 6. Report additions

On top of the standard report (incidents first):
- a **fix verification table** (commit → row → status → build)
- the **redesign regression matrix**: each surface × the base pass plus its triggered escalations, and the reason each untriggered check was skipped
- **API-level differences**
- **reusable assets**: the AVDs, the snapshots, and the build commands that worked
