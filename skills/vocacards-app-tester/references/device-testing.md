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
  worktree-needs-node-modules-and-env). Junction `node_modules` to the main checkout and
  copy `.env` and `.env.local`, then **always start Metro with `--clear`**. The junction
  shares Metro's transform cache, so a plain start can serve another worktree's code as a
  normal-looking bundle.
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
- **`/status` 200 isn't health.** A long-running Metro can answer it while the device
  goes black. An old Metro can also stop spawning children (0xC0000142), which looks like
  a laggy app. If runs behave oddly, restart Metro and reboot the device **before** you
  bisect code (memories: metro-health-check-lies, metro-spawn-failure-long-sessions).
- **Launching.** The dev-client deep link sometimes silently no-ops. The fallback is
  `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`, then tap the server
  row. An `am start` after a force-stop lands on the **dev-launcher screen**, not the app
  (test-validity-rules register). Unlock the device first, because launching into a
  locked device lands on an error screen.

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

## 12. E2E guard

`e2e/run-guard.sh` (Git Bash) restores the Phase13 fixture, drives the Deck Inspector
drag with Maestro, and asserts live SQLite state. It needs an emulator, the debug APK,
Metro, Maestro and Java 17 (`e2e/README.md`). It's mandatory after SDK hops, and it's the
model for a device test whose verdict is a DB assertion rather than a screenshot.
