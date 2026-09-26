# Full device test plan (mode E: campaign)

A complete on-device QA campaign for VocaCards, split into about 150 test cases with IDs.
Use it when the owner asks for "everything" on a test device. It runs across **as many
agent sessions as it takes**, held together by a ledger. It's written for one Android test
phone that has both the Play-installed release app and the dev client.

The first campaign (2026-09-25) ran 30 minutes and left 14 of ~30 areas NOT RUN, with
"no time" as the reason. This plan exists so that can't happen quietly again.

## Contents

1. Campaign rules: ledger, definition of done, sessions
2. Unblockers (run first)
3. Test catalog (IDs, steps, pass conditions)
4. Order of execution

## 1. Campaign rules

**Ledger.** `STATE.md` in the run folder is the single source of truth. It holds one row
per test ID in the format `ID | status | evidence | note`.
- Create it from §3 at the start of the first session. Every ID starts as `TODO`.
- Update the row **immediately after each test**, not in batches, so a session that dies
  mid-way loses at most one test.
- Every later session starts by reading `STATE.md` and `RUNLOG.md` and continues from the
  first open ID in the §4 order.

**Statuses.**
- `PASS`, `FAIL`, `NEEDS-HUMAN`.
- `BLOCKED(<blocker>; tried: <what you did to remove it>)`.
- `N/A(<why the feature doesn't exist in this build>)`.

**Definition of done.** Write the final report only when no row is `TODO`. These are
**not** valid reasons and don't count as done: "no time", "run length", "—", "not
attempted", "needs DB" (when a UI-level oracle exists), "needs a second device" (the dev
client *is* the second device).

**Sessions.** When your context is nearly used up:
1. Finish the current test and update its row.
2. Write a `## Checkpoint` block at the end of `STATE.md`: what's in flight, the device
   state, which apps are signed in, and the next ID.
3. Tell the owner "checkpoint written; send 'continue' to resume".

That handover is the only acceptable way to stop before done. A session that ends early
without a checkpoint is a defect of the run.

**Depth rules.** A test's minimum count is part of its pass condition. "Rate ≥ 5 per
grade" with 1 rating is `FAIL(harness)`, not PASS. If a DB oracle is unavailable, use the
listed UI oracle. Downgrade only to what the evidence supports.

**Evidence.** Every row cites a file in `shots/`, `dumps/`, `db/`, `logs/` or `perf/`. DB
assertions are written as a query plus its before and after output, saved as `db/<ID>.txt`.

**Lessons from the second campaign (2026-09-25/26).** It ran 10 hours with 0 TODO, but
two headline findings didn't survive review:
- **A blocker on one build isn't a blocker for the test.** 19 rows were BLOCKED because
  the dev client couldn't sign in, while the release app could. Run every signed-in, Power
  mode, cloud backup and purchase test on the release app. Only AC4 (two-device sync)
  needs both apps signed in.
- **Failures seen only on the dev client cap at PLAUSIBLE** until reproduced on the
  release app (SKILL.md §3). "The editor cannot save" was measured only on a dev client
  that had hit `database is locked`, and through a Save node with zero-size bounds.
- **Before calling a blocker external, try the documented workarounds**
  (`device-testing.md` §10b for the file picker, the clock and reminders; §10c for
  billing).
- **The report must match the ledger.** When a row is corrected (as U3 was, for "which
  Metro served the bundle"), update every report line that depended on it.
- **No tracked-file edits, even in the throwaway worktree.** Throwaway worktrees get
  their own `npm ci --offline`, never a junction; a junction is how the shared
  `node_modules` was destroyed.

## 2. Unblockers (run first, in order)

| ID | Goal | How | Done when |
|---|---|---|---|
| U1 | fg check trustworthy | Run `device.sh fg` against the app in front (expect exit 0) and after pressing HOME (expect exit 1). From PowerShell, read `$LASTEXITCODE` after `& bash …`, and never embed `$?` in a double-quoted string: PowerShell expands it first. | both controls behave |
| U2 | Debuggable dev client `cards.voca.app.dev` installed | 1) Look for an existing APK: `Get-ChildItem C:\tmp -Recurse -Filter *.apk` and check with `aapt dump badging` that the package is `cards.voca.app.dev`. 2) Otherwise build with `eas build --profile development-variant --platform android` and install the APK. This profile builds the dev client with `APP_VARIANT=development`. 3) Or build locally from a short path per `docs/android-build.md`. It installs alongside the release app, with a different package and no signature conflict. | `pm list packages` shows it, and `run-as cards.voca.app.dev true` succeeds |
| U3 | The dev client serves this tree | Create the throwaway worktree of master and run `npm ci --offline` in it (no junction). Start Metro there on its own port with `--clear`. Launch with the explicit `vocacards-dev://expo-development-client/?url=…` URL, then force-stop and relaunch once to clear any wedged DB. **Your** Metro log must show the device's bundle request after launch; the device also caches a bundle and may reconnect to a peer's 8081. | proof lines saved, including the bundle request |
| U4 | Release app is Play-installed and billing works | `dumpsys package cards.voca.app` shows installer `com.android.vending`, and the paywall shows a test card | shots |
| U5 | Import is reachable | Through the UI: the Library's "Choose deck file" row, which opens the picker in place. If it's hidden, enable it in Settings → caught-up (Power mode, signed in); see catalog §1 on the onboarding gates. Without the picker (dev client only): copy the deck into the app's own `cache/` with `run-as`, then open `vocacards-dev:///import?uri=file:///data/user/0/cards.voca.app.dev/cache/<f>.apkg&autoImport=1`. Record which path each import test used. | path proven once |
| U6 | Baseline | Pull the dev DB into `db/00-baseline`, with per-table counts. Screenshot the release app's decks, header and Stats. Inventory `/data/local/tmp` (`ls -la`) and create your own `/data/local/tmp/qa-<date>/` for every push. | files saved |
| U7 | Two devices on one phone | Sign the release app and the dev client into the same test account. If the dev client can't sign in (see the known SSO message in device-testing §10), run every signed-in test on the release app and block only AC4. | both show the account, or the fallback recorded |

If an unblocker fails, record its exact error, mark the tests that depend on it as
`BLOCKED(U<n>; tried: …)`, and **continue with everything that doesn't depend on it**.

## 3. Test catalog

"DB" = assert on a pulled dev-client DB. "UI" = assert from screenshots or dumps. Use the
release app for user-visible checks, performance and billing, and the dev client for DB
oracles.

### L — Lifecycle

| ID | Test | Pass when |
|---|---|---|
| L1 | Cold launch ×3 on each app | first screen correct, no crash, no error overlay |
| L2 | Warm launch after HOME | same screen and state |
| L3 | Background 60 s mid-edit and mid-review, then resume | draft and card preserved |
| L4 | `am kill` while backgrounded, then resume from recents | screen restores or falls back cleanly; no data loss (DB) |
| L5 | Rotate on every tab and on /add, /import, deck inspector, settings | no crash; layout per `docs/landscape-catalogue.md` |
| L6 | `am send-trim-memory <pkg> RUNNING_CRITICAL` mid-review | no crash, state intact |
| L7 | 20 background/foreground cycles in a row | no crash, no duplicate reviews (DB count) |

### F — Flow review

| ID | Test | Pass when |
|---|---|---|
| F1 | Rate **≥ 5 cards per grade** (Again/Hard/Good/Easy), each intended grade logged. Switch to the 4-button rating mode first: the default 2-button mode only offers left and right. Swipe slowly (≥ 800 ms; see device-testing §10b), because the rating buttons aren't in the accessibility tree. Also record that as an X6 finding. | one `reviews` row per rating, with the grade matching the log (DB count = 20+) |
| F2 | State transitions per grade | new→learning/review, and `due_at`, `reps`, `lapses`, `stability`, `difficulty` move in the right direction for each grade (DB) |
| F3 | Header vs queue | after force-stop and relaunch, the header equals `probe-queue-divergence.ts` on the pulled DB |
| F4 | An Again card returns after its learning step (~60 s) | served again only after the step; the LEARN count may lead it (known) |
| F5 | Undo or back-rate, if the UI offers it | DB row removed or reverted, and the card restored |
| F6 | Caught-up page | shown only when nothing is servable; a nonzero header plus caught-up means an invisible card (tap test) |
| F7 | Reviews/day cap = 3 with more due. The control is in Power mode, which requires sign-in, so use the release app. | exactly 3 Review-state cards served; learning cards bypass it (DB) |
| F8 | New/day cap per deck | served new = cap per deck (DB) |
| F9 | Paused subdeck | excluded from the queue and the header counts |
| F10 | Cards with audio, cloze and image occlusion | render, play and flip; no blank WebView after a tab switch |
| F11 | Long card: font 1.25× plus landscape | body scrolls with a slow `motionevent` drag, and a control ScrollView scrolls too |
| F12 | 10-minute session with ≥ 30 ratings, then compare the header with a fresh relaunch and the DB | equal, or stale-snapshot reproduced (known) |
| F13 | 50 rapid swipes in a row | no crash; ratings = DB rows; no stuck card |

### S — Special sessions and filters

| ID | Test | Pass when |
|---|---|---|
| S1 | Learn more (dealt) | the extra cards are dealt, and the counts make sense |
| S2 | Practice | practice ratings don't change FSRS state (or match the documented behaviour) (DB) |
| S3 | Preview tomorrow | shows tomorrow's cards; no FSRS writes, unless documented |
| S4 | Change the deck filter during each session | the session ends (#179) |
| S5 | A session survives the /add round-trip | same session after returning |
| S6 | A just-added card under tag chips | appears only under its own tags |

### A — Add card

| ID | Test | Pass when |
|---|---|---|
| A1 | Manual add, in ≥ 3 languages | card persists with the right `lang` and tags (DB) |
| A2 | Dictionary lookup online | entries fill; `lexical_entry_id` and `sense_key` set (DB) |
| A3 | Lookup offline | a clear message, not a hang |
| A4 | Duplicate detection | duplicate flagged; the edit-duplicate path works |
| A5 | Language rail and keyboard | preview doesn't jump; the rail stays usable with the keyboard open |
| A6 | Back to the Flow after an add | the new card is served and counted |
| A7 | Discard mid-add | no row created (DB) |

### E — Editing

| ID | Test | Pass when |
|---|---|---|
| E1 | Edit a vocab card | fields persist (DB) |
| E2 | Edit a dictionary-backed card's translation only | `lexical_entry_id` and `sense_key` unchanged. **Known open bug: they become NULL.** Report REPRODUCED/FIXED. |
| E3 | Edit an Anki note field | every sibling sharing `source_id` updates, each with its own derived text (DB) |
| E4 | After E3 | `anki_fields_original_json` set once; `anki_user_edited = 1` (DB) |
| E5 | Add or remove a cloze ordinal | save blocked with explicit copy |
| E6 | Revert to imported | original restored; the flag cleared or documented (DB) |
| E7 | Field modes | a plain, a formatted (bold kept), a media (`♪` anchor delete removes the token) and a rich (raw HTML) field each round-trip (DB) |
| E8 | Edit, then re-import the same deck | edited note kept, untouched notes refreshed (DB) |

### I — Import

| ID | Test | Pass when |
|---|---|---|
| I1 | Import discoverability: after a default onboarding, in Simple and in Power mode, with ≥ 1 card | the Library import row is visible, or there's a visible way to show it. Screenshot every place a user would look. |
| I2 | `legacy2-scheduled.apkg` | all 7 cards match `tests/fixtures/anki/ground-truth.json` (state, reps, lapses, stability, difficulty, due, revlog count) (DB) |
| I3 | `latest-scheduled.apkg` (v18, zstd) | same comparison as I2 |
| I4 | `multideck.colpkg` | decks and subdecks created as in the fixture; card counts match |
| I5 | CSV edge cases: BOM, quoted comma, empty row, non-Latin script, 1,000 rows | rows as expected, no mojibake (DB) |
| I6 | Truncated `.apkg` | clean error; zero partial rows (DB counts equal before and after) |
| I7 | Re-import after reviews and an edit | progress kept, edits kept, content refreshed (DB) |
| I8 | Repeat the import 5× under different names | no "database is locked"; time per import recorded |
| I9 | Cancel mid-import, and kill the app mid-import | no half-imported deck, or a documented resume (DB) |
| I10 | Import offline | works (it's local) or fails clearly |

### D — Decks and presets

| ID | Test | Pass when |
|---|---|---|
| D1 | Drag-reorder subdecks, then relaunch. This needs a deck with ≥ 2 subdecks, so import `multideck.colpkg` (I4) first. | `subdeck_order::…` persisted (DB, `e2e/assert-db.mjs` model) |
| D2 | Pause, then unpause | `subdeck_state::…` persisted; queue and header follow |
| D3 | Deck preview | cards render; editing from the preview routes by `sourceType` |
| D4 | Manage cards: search, filter, open | results correct |
| D5 | Create a preset, bind it, rebind to global | `tag.preset_id` correct; no dangling id (DB) |
| D6 | Change FSRS params and steps | persisted, and the next interval reflects them (DB) |
| D7 | Delete a deck | its cards and `card_tag` rows gone, other decks intact, no dangling preset (DB) |
| D8 | Reset progress on a card | FSRS fields reset per spec (DB) |
| D9 | Merge or rename decks, if offered | tags and `primary_tag` consistent (DB) |

### B — Backup and restore

| ID | Test | Pass when |
|---|---|---|
| B1 | Local export | file created; size and time recorded |
| B2 | Local restore round-trip: pull A, export, mutate, restore, pull B. The restore goes through the file picker, so use device-testing §10b if it ignores taps. | per-table counts equal; 50 sampled `cards` rows equal on every column; `card_tag` identical; presets resolve (DB) |
| B3 | Connect Drive (test Google account) | connected, or the stale-build OAuth cause identified |
| B4 | Backup folders: create, list, delete | UI and Drive agree |
| B5 | Cloud backup | "Last backup" updates; duration recorded |
| B6 | Local reset, then cloud restore | same comparison as B2 (DB), or counts and Stats (UI) |
| B7 | Sign out and in, then cloud restore | decrypts (per-user key re-fetched); any "can't decrypt" is 🔴 |
| B8 | Automatic backups and rotation, if offered | oldest removed, newest never |
| B9 | Backup offline | a clear error, no corrupt partial |
| B10 | Kill the app mid-restore | the app recovers to a consistent state (DB) |
| B11 | Media survives a restore (IO or audio cards) | media plays and renders after restore |

### AC — Account and sync

| ID | Test | Pass when |
|---|---|---|
| AC1 | Offline sign-out | blocked with a message; no half-state |
| AC2 | Online sign-out | documented local-data behaviour; theme and settings reset through a JS reload |
| AC3 | Sign back in | study data replays; review counts and card states match the pre-sign-out pull (DB) |
| AC4 | Review on the release app, then check the dev client (and the reverse) | change arrives; latency recorded; foreground requirement documented (DB) |
| AC5 | Device slots on free | claim, refusal and messaging per `docs/DECISIONS.md` Suite 3 |
| AC6 | Device slots on Pro | per Suite 3 |
| AC7 | Full local reset | wipe plus JS reload; sign-in works after |
| AC8 | **Account deletion (last test of the campaign)** | disclosure shown; local wipe; signed out; no Pro. NEEDS-HUMAN: Convex rows, RevenueCat and Clerk checks. Don't sign in again afterwards. |

### P — Purchases (release app, Play license tester)

| ID | Test | Pass when |
|---|---|---|
| P1 | Every paywall entry point | offerings and prices render; close, back and rotate are safe |
| P2 | Test card, always approves | Pro in the app; time recorded; survives relaunch |
| P3 | Test card, always declines. Tap the payment-method row on the sheet to list every test card. | clear error; stays free |
| P4 | Slow test card (same list) | pending UI, then Pro |
| P5 | Cancel the purchase sheet | no change |
| P6 | Purchase offline | clear error |
| P7 | Within one accelerated period of a fresh purchase (record both times): sign out and in; then `pm clear`, sign in, Restore purchases | Pro restored both times; Restore reports its result (success, or "nothing to restore") |
| P8 | Accelerated renewal observed (the sheet shows the period, for example "/5 min") | renewal visible; Pro continuous |
| P9 | Cancel in Play Store → Payments & subscriptions | Pro lapses at period end; lag recorded. Test subscriptions also lapse on their own after a few renewals, so time every "Pro gone" against the purchase clock. |
| P10 | Pro gating | every Pro feature locked on free and unlocked on Pro (list them) |
| P11 | Paywall in the dev client (no billing) | fails gracefully |

### T — Settings

| ID | Test | Pass when |
|---|---|---|
| T1 | Every toggle and field on every settings screen (list each one) | persists across force-stop and relaunch |
| T2 | Re-open each screen right after a change | no stale first frame reverting it |
| T3 | Day-rollover hour | the "today" boundary moves (header and Stats) |
| T4 | Caught-up settings | behaviour follows |
| T5 | Card options (font scale and more) | applied on card faces, including WebView cards |
| T6 | Mode: Power vs Simple | UI changes as designed |
| T7 | App language | UI strings change; no hard-coded English |

### ST — Stats

| ID | Test | Pass when |
|---|---|---|
| ST1 | Today's reviews | equal to `reviews` rows today (DB) |
| ST2 | Streak | agrees with `dailyStats` and the Flow hero |
| ST3 | Forecast | agrees with the `due_at` histogram (DB) |

### CP — Capture, inbox, course

| ID | Test | Pass when |
|---|---|---|
| CP1 | Share text into the app (`am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "…" <pkg>`) | capture lands in the inbox with its sentence |
| CP2 | Inbox actions: make a card, dismiss | card created and inbox updated (DB) |
| CP3 | Camera or OCR capture (grant permission) | text captured, or a clear failure |
| CP4 | Capture offline, then online | queued, then drained, with no duplicates (DB) |
| CP5 | Create course (Gemini) end to end | deck created and bound to a preset (DB) |
| CP6 | Capture or bridge pairing that needs a desktop | NEEDS-HUMAN, with steps |

### N — Notifications

| ID | Test | Pass when |
|---|---|---|
| N1 | Set a reminder | `dumpsys alarm` shows the registration |
| N2 | Reminder fires: set it 2–3 minutes ahead (no time travel needed), then background the app | notification posted |
| N3 | Tap the notification with the app killed | opens to the Flow |
| N4 | Notification permission denied | the UI explains it; no crash |

### NAV — Navigation

| ID | Test | Pass when |
|---|---|---|
| NAV1 | Android back on every screen, sheet and modal | closes the innermost layer first |
| NAV2 | Unsaved-edit guard | prompts before discarding |
| NAV3 | Deep links to every route, with valid, malformed and missing params | no crash; sensible fallback |
| NAV4 | Tab switching | Stream state retained; the card-entry slide replays (by design) |
| NAV5 | Every feature reachable from a non-empty state | list every entry point per feature; anything only reachable from an empty state, or hidden by a gate with no visible way back, is a finding |

### X — Cross-cutting UI

| ID | Test | Pass when |
|---|---|---|
| X1 | 4 themes × 4 styles on Flow front and back (vocab + cloze), Settings, deck inspector, Add, paywall, onboarding | 96+ shots; no clipping or contrast failure |
| X2 | Noir chrome audit | no green on non-pressable chrome |
| X3 | Fixed-box text (badges, circles, steppers, pause chip) at the largest font in Book | glyphs centred |
| X4 | `font_scale` 1.0 / 1.3 / max on the X1 screens | no new overflow compared to 1.0 |
| X5 | `uiautomator dump --compressed` on every screen (plain control once) | findings listed |
| X6 | Label and target census | every icon-only control labelled; targets ≥ 48 dp including hitSlop |
| X7 | TalkBack traversal of the main screens | sensible focus order; the Flow card gradable without gestures (or noted as a standing proposal) |
| X8 | Landscape catalogue | per the doc |
| X9 | System dark/light flip with the app open | themes react as designed. The app uses its own four themes and ignores system dark mode, so mark this N/A unless a "follow system" option exists. |
| X10 | Force RTL (Developer options) | no mirrored-layout breakage in chrome |

### PF — Performance (release app; n ≥ 5, median and range, detection floor stated)

| ID | Test | Pass when |
|---|---|---|
| PF1 | Cold start `am start -W` ×7, interleaved | median and range recorded |
| PF2 | Flow swipes: gfxinfo reset, then 3 blocks of 20 | p50/p90/p95/p99 and Missed Vsync |
| PF3 | Deck-list fling | same metrics |
| PF4 | Memory: VmRSS and VmHWM every 5 s for 5 minutes | max recorded |
| PF5 | PF1 and PF2 again after the I8 imports | delta, with the floor |
| PF6 | Queries per swipe (dev `[queue-perf]`) | a count |
| PF7 | Backup and restore durations (local, cloud) | recorded |

### TT — Time travel (system clock; after P and B)

Move the clock through Settings → Additional settings → Date & time, not adb: `date` and
`su` fail on retail MIUI (device-testing §10b). Restore automatic time and read it back.

| ID | Test | Pass when |
|---|---|---|
| TT1 | +1 day | due cards appear matching `due_at` (DB); rollover hour respected; streak rule correct; reminder fires |
| TT2 | +7 days | backlog and caps sane; streak broken correctly |
| TT3 | +30 days | Stats and forecast sane; no crash |
| TT4 | Back to automatic time | no duplicated or lost reviews (DB count) |
| TT5 | Timezone change (auto zone off) | "today" boundary follows the app's rules |

### FI — Fresh install and onboarding

| ID | Test | Pass when |
|---|---|---|
| FI1 | `pm clear`, then onboarding end to end (language, account, Pro screen, first deck or course) | completes; each screen shot |
| FI2 | Known: onboarding stamps an archived deck without content | REPRODUCED/FIXED |
| FI3 | Empty states: no decks, nothing due | helpful copy; the Get started import entry works |
| FI4 | First launch offline | usable, or a clear message |

### SX — Stress

| ID | Test | Pass when |
|---|---|---|
| SX1 | Monkey, release app, **signed out, with a screenshot of the signed-out state before each seed** (signed in, it reached sign-out in one campaign; if you can't sign out, don't run it), seeded with fixtures: 3 seeds × 5,000 events (`--pct-syskeys 0 --pct-appswitch 0 --pct-anyevent 0 --throttle 150`) | crashes and ANRs listed with seeds |
| SX2 | Import during an active review session | no "database is locked"; both complete |
| SX3 | 100 ratings in one session (dev) | DB rows = ratings; no drift in the header |

### K — Known issues (verdicts)

K1 edit strips pack identity (E2) · K2 LEARN overstatement (F4) · K3 stale snapshot (F12)
· K4 special-session card stranded low · K5 #179 (S4) · K6 restore carries all columns (B2)
· K7 reviews/day cap scope (F7) · K8 onboarding archived deck (FI2) · K9 OAuth "signed in"
card on release · K10 Library import rows hidden after onboarding (I1) · K11 audio button
unlabeled (X6).
Each gets REPRODUCED / FIXED / NOT TESTABLE, with evidence.

## 4. Order of execution

State flows forward, so this order keeps destructive steps late:

U1–U7 → L → F → S → A → E → D → ST → T → NAV → CP → N1 → I (needs `pm clear` for the
first import; re-seed after) → B → AC1–AC7 → P → X → PF → TT → FI → SX → K verdicts →
**AC8 last**.

Phase 13 (root cause by reading), Phase 14 (restore and clean up) and the report follow,
as in the driver prompt.
