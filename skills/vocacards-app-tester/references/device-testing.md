# Device testing runbook

Read this before the first adb command. Every recipe here was bought with an incident or
a wasted session. The originals are in the memory directory; the names are cited so you
can read the full story.

## Contents

1. Decide whether to drive the device at all
2. Devices, packages and roles
3. Preflight: toolchain, Metro, the right bundle
4. Safety before any input
5. Gestures
6. Reading state: DB, logs, counters
7. Accessibility checks
8. Visual and feel checks
9. Performance measurement
10. Known non-bugs
    10b. Driving system UI (file picker, clock, reminders)
    10c. Billing tests (Play license tester)
11. Builds and installs
12. E2E guard

## 1. Decide whether to drive the device at all

Default to the cheap end (memory: ask-user-to-verify-on-device). Diagnose by reading the
code, make the change, reload, then **ask the user one specific question**. They have
the phone in hand. An adb loop costs minutes and often can't see the defect: screencap
tops out near 10 fps, there's no ffmpeg, and a synthetic swipe lands differently from a
finger.

Drive the device yourself only for:
- one screenshot to confirm something rendered,
- a DB pull to check persisted state,
- a count you can read exactly (rows written, calls made),
- an instrumented probe that kills a hypothesis in one reload.

When the symptom is ambiguous ("something flickers"), ask what they see before you
instrument anything.

## 2. Devices, packages and roles

| | POCO | Redmi Note 8 Pro |
|---|---|---|
| adb serial | `6787ed3b` (`marble`, 1080×2400) | `h6z5mnproz6l4hif` (`begonia`) |
| default role | test device, disposable data | second device, disposable |
| note | currently runs a **release** build, so `run-as` is refused | dark theme on this handset; foreground key is `mResumedActivity`, not `topResumedActivity` |

- **Packages:** release `cards.voca.app` (scheme `vocacards`). Dev variant
  `cards.voca.app.dev` (scheme `vocacards-dev`, built with `APP_VARIANT=development`).
  Target the component explicitly (`am start -n cards.voca.app.dev/.MainActivity …`), or
  Android may hand the deep link to the release app. Check
  `dumpsys window | grep mCurrentFocus`.
- **Roles are per task.** The sync/backup campaigns name the POCO **Device A, PROTECTED**
  (read-only: no wipe, restore, sign-out or mutation) and route destructive work to the
  Redmi. When a prompt assigns roles, the prompt wins (memory: poco-is-a-test-device).
- **Freeze the protected device before editing trigger-reachable code.** Metro is often
  already attached to it, so an edit to backup, rotation or sync code hot-reloads into it,
  and its next trigger runs your new path against real artifacts. Run
  `adb -s <protected> shell am force-stop cards.voca.app`, and tell the user it's stopped.
- **Devices are shared with other sessions.** Several Claude sessions drive these phones
  at the same time. An unexpected app or variant in front may be a peer's run, not a
  bug. Before a device run, check `ListAgents` and ask whoever might be on it. Answer
  device questions from peers promptly.

## 3. Preflight: toolchain, Metro, the right bundle

`bash scripts/device.sh preflight <serial>` (in this skill's directory) runs the
read-only checks below and prints what it finds.

- **PATH in agent shells.** Agent shells don't source a profile.
  - adb: `export PATH="$PATH:/c/Users/Luk/AppData/Local/Android/Sdk/platform-tools"`
  - Node 22 (for `better-sqlite3` and tests):
    `export PATH="$HOME/AppData/Roaming/fnm/node-versions/v22.23.1/installation:$PATH"`
  - Git Bash: `MSYS_NO_PATHCONV=1` for any command with a device path (`/sdcard`,
    `/data/local/tmp`). Without it the path is rewritten to a Windows path and silently
    misses.
- **A worktree can't run the app until you set it up** (memory:
  worktree-needs-node-modules-and-env). It needs `node_modules` plus copies of `.env` and
  `.env.local`. Then **always start Metro with `--clear`**.
  - **For a QA worktree you create yourself, run `npm ci --offline` inside it.** The npm
    cache holds every package, so it doesn't touch the network.
  - **Don't junction `node_modules` into a throwaway tree.** On 2026-09-26,
    `git worktree remove --force` followed such a junction and deleted about 190 packages
    from the shared checkout (575 → 382 entries).
  - Any recursive delete (`Remove-Item -Recurse`, `rm -rf`, `rmdir /s`) can do the same.
    If a junction exists, remove it first with `cmd /c rmdir <link>` (without `/s`, which
    deletes only the link). Then confirm that `cmd /c dir /AL /S /B <tree>` lists nothing
    before deleting the tree.
  - A shared junction also shares Metro's transform cache, so a plain start can serve
    another worktree's code as a normal-looking bundle.
- **Metro binding.** Never use `--localhost`: on this host it binds IPv6-only and
  `adb reverse` gets nothing. Use the `expo` launch config or `--host lan`, then
  `adb reverse tcp:<port> tcp:<port>` (re-assert it after relaunches, because it drops).
  Verify **from the device**:
  `adb shell "curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:<port>/status"`
  should print 200, and `netstat -ano | grep <port>` should show `0.0.0.0`.
- **:8081 may be a peer's Metro** (memory: metro-health-check-lies). Check with
  `curl -s ':8081/index.bundle?platform=android&dev=true' | head -c 300`. A 404 whose
  `originModulePath` is someone else's directory means it isn't yours. Don't kill it.
  Start your own on another port (8082 and up) and point the dev client at it.
- **Prove the device runs your code** (memory: devclient-stale-bundle). The only positive
  proof is output from the new code: a temporary `console.log` that lands in
  `.expo/dev/logs/start.log` (JSONL, UTF-8). A fresh `Bundled` line after a save shows
  the watcher saw it. A curl of the bundle proves nothing, because the curl itself
  triggers a rebuild. If it's stale: `--clear`, force-stop, cold relaunch, then wait for
  the full multi-thousand-module `Bundled` line.
- **Which server did the device actually load?** The dev launcher reconnects to the last
  server it used, and a peer's Metro on 8081 won one campaign. It also keeps a ~20 MB
  cached bundle (`files/DevLauncherApp-*DevBundle.js`) that runs with no server at all.
  Launch with your explicit URL, then confirm that **your** Metro's log shows a bundle
  request arriving right after the launch. A healthy server is not proof the device used
  it.
- **`/status` 200 isn't health.** A long-running Metro can answer it while the device
  goes black. An old Metro can also stop spawning children (0xC0000142), which looks like
  a laggy app. If runs behave oddly, restart Metro and reboot the device **before** you
  bisect code (memories: metro-health-check-lies, metro-spawn-failure-long-sessions).
- **Launching.** The dev-client deep link sometimes silently no-ops. The fallback is
  `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`, then tap the server
  row. An `am start` after a force-stop lands on the **dev-launcher screen**, not the app
  (test-validity-rules register). Unlock the device first, because launching into a
  locked device lands on an error screen.
- **Deep links beat scrolling.** Both builds route by scheme: `vocacards:///<route>`
  for release, `vocacards-dev:///<route>` for the dev client. For example
  `vocacards:///settings/backup` goes straight to the backup screen, while the Settings
  rows shift with the Pro banner. Open modals through the real UI, though (§7).

## 4. Safety before any input

- **Foreground check, every batch.** `bash scripts/device.sh fg <serial> [package]` exits
  non-zero unless the package is in front, and checks both the
  `topResumedActivity`/`mResumedActivity` keys and `mCurrentFocus`. Chain your input
  behind it: `bash …/device.sh fg 6787ed3b && adb -s 6787ed3b shell "input tap …"`.
  *Why:* on 2026-09-14 a tap sequence landed in the user's crypto exchange app and a
  screenshot captured balances (memory: adb-verify-foreground-app). If another app is in
  front: stop, delete any screenshot of it, tell the user, and ask before continuing.
- **Screenshot before the first tap, and after every navigation.** Coordinates go stale
  between builds. A dark or sleeping screen swallows a whole sequence, and then one later
  tap lands somewhere real: it once flipped Settings → Mode from Power to Simple. If a
  blind tap did land, diff the screen against an earlier capture to find what it changed
  before moving on. `svc power stayon true` doesn't reliably hold MIUI awake.
- **No horizontal swipes on the Flow** while a card is showing. Left is "Again", right
  is a pass rating, and both are real reviews. Pure-vertical drags (dx = 0) are safe. The
  deck browser and Settings are safe to script.
- **Long-press trap.** Keep a whole gesture (DOWN…MOVE…UP) inside **one**
  `adb shell "…; …"` call. Across separate invocations the gap exceeds `delayLongPress`
  (500 ms), and a tap becomes a long press. That once opened an action sheet and paused
  the wrong deck.
- **Destructive steps** (deck delete, wipe, restore, sign-out) only on a device the task
  marks disposable. Announce each one first.
- **`/data/local/tmp` is shared with other sessions' experiments.** Push everything into
  your own `/data/local/tmp/qa-<date>/`, and clean up by deleting only that folder. Never
  glob-delete `/data/local/tmp`: one campaign deleted two older files it hadn't created.
- **Random-tap stress (monkey) runs signed out, with evidence.** Screenshot the
  signed-out state before each seed. Signed in, monkey can reach sign-out, account
  deletion and purchases. If you can't get signed out, don't run it.
- **Harness lessons from the 2026-09-25 Codex run.** Each of these was caught only by a
  control:
  - *Calling bash from PowerShell.* PowerShell expanded `$?` inside a double-quoted
    `bash -c "…; echo $?"` before bash saw it, so `fg` looked like it always returned 0.
    Read `$LASTEXITCODE` after `& bash …` instead.
  - *A dead-looking button.* Tap a sibling control at the same y. If that also does
    nothing, your coordinates are wrong, not the button.
  - *A black screenshot* means the screen is asleep. It's not a rendering bug.
  - *Failed settings writes.* A `settings put` that prints an error was not applied.
    Read every restored value back, because the first restore pass silently failed one.

## 5. Gestures

Memory: adb-gesture-testing-motionevent.

- `input swipe` is a fast, perfectly straight drag. It wins races a real finger loses,
  so a pass proves nothing about arbitration. Use `input motionevent` with a few px of
  sideways wander on the first moves, all in one call:
  `adb shell "input motionevent DOWN 500 1700; input motionevent MOVE 512 1704; input motionevent MOVE 519 1698; …; input motionevent UP 507 1000"`
- Run a control: the same drag on a plain ScrollView screen. If the control fails too,
  the simulation is wrong, not the app.
- **Read gesture state mid-drag.** A screenshot after `UP` is worthless, because the
  Pressable underneath fires `onPress` on release. Screencap on the device inside the
  same shell call, with the finger still down (`…; sleep 2; screencap -p /sdcard/held.png;
  input motionevent UP …`).
- `motionevent` gives one coarse ~36 dp move per call, far coarser than a finger. When
  event granularity is the variable, hand it to the user.
- To force the card body to overflow so scrolling is observable: Card options → font
  1.25× plus landscape.

## 6. Reading state: DB, logs, counters

- **Pull the DB** (debuggable builds only):
  `bash scripts/device.sh pulldb <serial> [package] [outdir]`. It copies the `.db`,
  `-wal` and `-shm` through `/data/local/tmp` and cleans up after itself. Never use
  `adb exec-out … cat > file` in Git Bash: the output has the right size and a valid
  header but is **silently corrupt** (empty `sqlite_master`). Always take the `-wal`,
  because recent writes live there. Query with `better-sqlite3` (Node 22) from the repo
  root, or compare with `npx tsx scripts/probe-queue-divergence.ts`.
  - **On the Redmi (MIUI), `run-as` can't write to `/data/local/tmp`** (measured
    2026-09-26), so `device.sh pulldb` fails there. Stream the file instead, through a
    **byte-exact** redirect:
    `cmd /c "adb -s <id> exec-out run-as <pkg> cat files/SQLite/vocacards.db > C:\…\vocacards.db"`.
    Use the same form for the `-wal`. cmd.exe's `>` is byte-exact; Git Bash's `>` and
    PowerShell 5.1's `>` are not.
  - Validate every pull with `PRAGMA integrity_check` **and** a row count. Size and
    header checks pass on a corrupt copy.
  - The database lives in `files/SQLite/`, not `databases/`.
- **Release build (no `run-as`).** The app's UI is the instrument. For timing, render a
  `mark()` ring buffer as small monospace text inside the body that's on screen during
  the bug, then read it from one screencap. Build and install, then revert the probes
  straight away and save the diff to the scratchpad first (memory:
  release-build-trace-overlay).
- **Logs.** `console.log` never reaches logcat; only `console.error` does. Dev logs go to
  `.expo/dev/logs/start.log` (JSONL). `[queue-perf]` timings are already in there.
  `metro:bundling:done` lines prove which code was live when. A Metro *terminal* log
  captured with PowerShell `Tee-Object` is UTF-16, so an ASCII grep returns 0.
- **Counters.** Force-stop and relaunch before trusting any on-screen or logged counter.
  A long-running session can read a stale SQLite snapshot and never see its own writes
  (memory: app-reads-stale-sqlite-snapshot). The LEARN header also overstates the
  servable queue for ~10 min after an Again.
- **Invisible card vs session end.** Caught-up page plus a nonzero header means a card is
  mounted at opacity 0. One tap in the card area tells you: if it reappears, it was
  invisible (memory: diagnosing-invisible-card-on-flow).
- **Readiness gates** must work in the build you're measuring. `[stream-debug]` logs
  exist only under `__DEV__`, brightness tests fail on a dark theme, and the Android home
  screen passes a "bright band" test. Run a negative control (app stopped) and a positive
  control (app up) before trusting any gate (test-validity-rules register).
- **Zero-size nodes aren't evidence.** `enabled`, `selected` and `checked` read from a
  uiautomator node whose bounds are `[0,0][0,0]` are unreliable; the editor's Save and
  Cancel were such nodes. Judge the control by what tapping it does (a DB row or a visible
  change). Take the tap coordinates from a visible sibling, not from the node.
- **Custom switches report `checked=false` even when visibly ON** (2026-09-26). Read
  their state from a screenshot, and record the mismatch as an accessibility finding:
  a screen reader gets the same wrong state. The rating buttons are missing from the
  tree altogether (§10b).
- **`run-as` can write to the app's own `cache/`** but not to `/data/local/tmp` on the
  Redmi. Stage files for the dev-only import deep link there.
- **The dev client's DB can wedge.** After reloads it can hit `DB init failed … database
  is locked`, and writes may then hang silently. Before any write test on the dev client,
  force-stop it, relaunch, and prove one write lands (a DB count). Once a lock has been
  seen, treat any write-path failure as SUSPECT until you reproduce it on the release app.
  A "the editor cannot save" verdict came from exactly this state.
- **Dev-client-only failures cap at PLAUSIBLE.** The dev client runs a native shell that
  may be older than master, a JS bundle from whichever server it reached, and a DB that
  wedges. Before rating a failure High or above, reproduce it on the release app, or show
  the mechanism in code.

## 7. Accessibility checks

- For "what does TalkBack see", use `uiautomator dump --compressed`. A plain dump
  includes not-important views, so it isn't TalkBack evidence. A fix was once built for
  a bug that existed only in a plain dump. Run the same dump without the fix as a
  control (memory: uiautomator-compressed-for-a11y).
- Open modals through the real UI. A deep link straight to a modal route has nothing
  mounted under it, which gives false passes.
- Touch targets ≥ 48 dp are measured from layout-dump bounds plus `hitSlop`, not by regex
  over source. Test text scaling at `font_scale` 1.3 and at the device's largest setting.

## 8. Visual and feel checks

- **Visual:** capture HEAD and the change on the same device, both from a cold relaunch,
  with the same theme, style and font scale. `scripts/design-lab/capture.mjs`,
  `pixel-diff.mjs` and `rects-diff.mjs` exist for this. A diff that is *too large* for
  the change is measuring navigation or scroll state, not code.
- **Feel** (swipe, motion) is a human instrument. Use a blinded A-B-B-A with 20–30
  gestures per leg so adaptation decays. Have the judge rate **one named attribute**
  ("how the next card rises into place"). First verify that the two builds produce
  *different numbers in the condition being judged*: one T2 run compared two identical
  builds under a portrait lock (test-validity-rules, rule 9).

## 9. Performance measurement

- **Dev build numbers aren't product numbers.** Release is ~5.3× faster tap-to-card, and
  "freezes after a few swipes" was mostly dev-client overhead. Make perf claims on a
  release build (memories: review-freeze-is-mostly-dev-build,
  stream-mount-cost-is-not-js).
- **Frame stats.** `dumpsys gfxinfo <pkg> reset`, drive, then dump. Read percentile tails
  and Missed Vsync, not "Janky frames %", which depends on duty cycle. On Android 15 the
  `framestats` CSV block is gone.
- **State the detection floor before you run.** Interleave A/B pairs and report the
  paired difference with its CI. n = 1 near a threshold is not a result
  (test-validity-rules, rules 5, 7 and 10). Prefer a count (queries per swipe,
  round-trips) where one exists. Each SQLite hop costs ~29 ms.
- **Memory.** VmHWM resets on this device. Poll VmRSS and VmHWM and take the max. Only
  the delta over the ~945 MB dev-client baseline means anything (memory:
  vmhwm-resets-on-this-device).
- **Keep the device awake** during long measurements (`svc power stayon true`, and check
  it held). Dozing looks exactly like a freeze.
- For frame-by-frame study: `adb shell screenrecord --size 540x1200`, pull, and decode
  with Python `cv2`. Use `CAP_PROP_POS_MSEC` per frame, not FPS, because screenrecord
  only emits frames on change.

## 10. Known non-bugs

Don't chase these as app defects:

- The `ReactActivityDelegate.onUserLeaveHint` NPE and the "last open crashed" dev-launcher
  warning are an expo-dev-launcher bug that doesn't exist in release. Relaunch.
- A Fabric SIGSEGV in `findNextFocusableElement` / `findShadowNodeByTag_DEPRECATED` is a
  dev-client focus-vs-reload race.
- Google/Apple sign-in skipping the "signed in" card happens in the dev client. Verify
  it in release.
- `DebugServerException … 404`, reported as "the build crashed", is a worktree with no
  `node_modules`, not a native problem.
- `Missing EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY` means the worktree has no `.env`.
- A `ClassNotFound MainApplication` at launch is a corrupt dex or poisoned `.cxx`: wipe
  the caches and rebuild arm64-only (memory: devclient-corrupt-build-recovery).
- **"expo-auth-session and expo-web-browser are required for SSO" on the dev client is
  misleading.**
  - `@clerk/expo`'s `useSSO` wraps the require in a bare `catch {}` that always prints
    this message, whatever actually threw.
  - `expo-auth-session` itself is pure JS, so it never appears in an APK.
  - The 2026-09-20 dev APK does contain every native module it needs: ExpoCrypto,
    ExpoCryptoAES, ExpoLinking, ExpoWebBrowser (checked in the dex).
  - The real cause is unknown. Diagnose it in React Native DevTools with "pause on caught
    exceptions". Meanwhile, run signed-in tests on the release app, which signs in fine.
- On the dev client, the dev-menu gear overlaps the Flow's "Filter decks" control, so a tap
  there opens the dev menu. Run filter tests on the release app.

## 10b. Driving system UI

- **The file picker (Android DocumentsUI) ignores taps on file rows.** One campaign lost
  every restore and import test to this. Try these in order and record which worked:
  1. Look for overlay windows. The picker may drop touches while something draws over
     it. Check with `adb shell dumpsys window windows | grep -i -E "overlay|Window #"`.
     Stop `screenrecord`, turn off "Show taps" and "Pointer location", and close floating
     bubbles.
  2. Tap with an explicit `input motionevent DOWN x y; … UP x y` in one shell call.
  3. Use the keyboard: `input keyevent 61` (TAB) or `20` (DPAD_DOWN) to focus the row,
     then `66` (ENTER).
  4. Use the picker's search to narrow the list to the one file, then ENTER.
  5. For imports on the dev client only, skip the picker: copy the file into the app's
     own `cache/` with `run-as`, then use the `/import?uri=…&autoImport=1` deep link.
     Try both `vocacards-dev:///import?…` and `vocacards-dev://import?…`, because one
     campaign saw the Add screen open instead.
- **The folder picker (SAF, used for local export) is harder than the file picker.** On
  the Redmi, its folder rows report `clickable=false` and ignore taps, `motionevent` and
  a forced initial URI. The file picker used by Import JSON and "Choose deck file" works
  on the same phone. Ways around it:
  - **Android 11+ refuses "Use this folder" on the storage root and on Download.** There
    the button just navigates, and no Allow dialog appears. Grant a **subfolder**. The
    recipe confirmed on the Redmi (2026-09-26): picker → New folder ("Nowy folder") →
    name it, which puts you inside it (check the breadcrumb) → "Use this folder" ("UŻYJ
    TEGO FOLDERU"; it may be off-screen, so scroll or check the dump) → Allow
    ("Zezwól"). The Allow dialog appearing is the proof that the grant happened.
  - Grants don't survive `pm clear`, so an earlier export's folder doesn't mean a live
    grant.
  - **Never hand-build an export file to test restore.** It would test your model of the
    format, not the app's, and could hide a column the real export drops. Use a real
    export, including one from an earlier run (they're kept under
    `qa-runs\…\db\B1-export.json` and `/sdcard/vcbackup/`). Restoring an older
    version's export into master is itself a useful cross-version test.
  - For a column-level restore check on the dev client, you don't need its export at all.
    Local exports are **plain JSON**. Pull the file from shared storage (no `run-as`
    needed), push it to `/sdcard/Download`, restore it through the file picker, pull the
    DB, and compare it with the JSON column by column.
- **Moving the clock without root.** `adb shell date` and `su` fail on retail MIUI. Use
  Settings → Additional settings → Date & time: turn off automatic time, then set the
  date. Verify with `adb shell date`. Turn automatic time back on at the end, and read it
  back.
- **Reminders without time travel.** The reminder time is an **hour-granular slider**
  (`profile.tsx`, 0–23), so set the next full hour and wait.
  - Kill the app with **`am kill`, never `am force-stop`**. Force-stop cancels the app's
    pending alarms (3 → 0, measured 2026-09-26), so the reminder can't fire and N3 becomes
    unobservable.
  - Check the registration with `dumpsys alarm | grep cards.voca`: there are 3
    RTC_WAKEUP alarms over the 3-day horizon.
  - Check delivery in the notification shade. Then tap the notification with the app not
    running.
- **Offline on MIUI.** MIUI ignores the AIRPLANE_MODE broadcast, so a "network off"
  command can report success while the phone stays online. Use `svc wifi disable` and
  `svc data disable`. Before any offline test, confirm with
  `adb shell ping -c 1 -W 2 8.8.8.8` that it fails, then read it back as working
  afterwards.
- **Rating cards on the Flow.** The rating buttons aren't in the accessibility tree,
  which is also an accessibility finding. In the 2026-09-26 run, only a slow swipe
  (longer than about 800 ms) committed a review. Use `input swipe x1 y1 x2 y2 900`, or a
  `motionevent` drag spread over at least 800 ms. Confirm every rating with a `reviews`
  count.

## 10c. Billing tests (Play license tester)

- **Test subscriptions run on an accelerated clock.** The purchase sheet shows the
  period, for example "27,99 zł/5 min". They renew only a few times, then lapse on their
  own. Record the purchase time, and judge any "Pro disappeared" against that clock and
  against Play Store → Payments & subscriptions before calling it an app bug. A
  "sign-out loses Pro" finding was really a lapsed test subscription.
- **The sheet shows one test card by default.** Tap the payment-method row to list the
  others (always declines, slow approve, slow decline). Only report "no decline card"
  after that list is open.
- **Account deletion ends the test account.** Later purchase tests need a fresh sign-in,
  which on this app creates a new account.

## 11. Builds and installs

- JS-only changes hot-load. Native modules, config plugins and OAuth schemes need a
  rebuild. Details are in `docs/android-build.md`.
- Build Android from a short path (`C:/tmp/...` checkout, with its own `npm ci` and
  `.env.local`). Building from `.claude/worktrees/*` hits MAX_PATH ("build.ninja still
  dirty") (memory: android-build-long-path). Don't set `JAVA_HOME` by hand. The
  environment already has JDK 17.
- **`adb install -r` keeps data only when the signing keys match.** Local release is
  signed with `signingConfigs.debug`. Check `apksigner verify --print-certs` against
  `keytool -list -v` **before** installing. A mismatch forces an uninstall, which wipes
  the collection.
- iOS is always an EAS round-trip. Assume any iOS dev client is stale (hence the
  lazy-require rule).
- **Building the dev client (`cards.voca.app.dev`) locally.**
  - `APP_VARIANT=development` must be set for `expo prebuild`. Without it,
    `app.config.js` builds the *release* package, with the production Google scheme:
    the collision `94162bc5` fixed.
  - Before building, check the generated `AndroidManifest.xml`. The package should be
    `cards.voca.app.dev`, with schemes `vocacards-dev` and
    `com.googleusercontent.apps.<dev id>`, and the production scheme absent.
  - A fresh tree needs `android/local.properties` (the SDK path), which is gitignored.
  - Sign with the same debug keystore as the installed dev client, so `install -r`
    keeps its data. That's `5E:8F:16:06:…:F6:25` on the Redmi as of 2026-09-26.
- **Drive on the dev client needs its own Google OAuth client.**
  - It must be an Android client for `cards.voca.app.dev`, registered with the SHA-1 of
    the key that **signs the dev client**, not `~/.android/debug.keystore`.
  - "Enable custom URI scheme" must be on, because the redirect is the reversed client
    id.
  - Its id goes in `.env.local` as `EXPO_PUBLIC_GOOGLE_OAUTH_DEV_CLIENT_ID`, in the tree
    Metro serves from. Restart Metro afterwards, since `.env` is read at startup.
  - The scheme is baked in at prebuild, so a new id also means rebuilding the dev
    client.

## 12. E2E guard

`e2e/run-guard.sh` (Git Bash) restores the Phase13 fixture, drives the Deck Inspector
drag with Maestro, and asserts live SQLite state. It needs an emulator, the debug APK,
Metro, Maestro and Java 17 (`e2e/README.md`). It's mandatory after SDK hops, and it's the
model for a device test whose verdict is a DB assertion rather than a screenshot.
