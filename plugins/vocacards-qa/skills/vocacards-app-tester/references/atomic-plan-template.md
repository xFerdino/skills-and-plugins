# Atomic plan template (mode H: a plan another agent runs)

Use this when the owner wants a test campaign written now and run later, often by a
different agent (Cursor, Codex, a fresh Claude session). It's distilled from the plans
that worked: `docs/qa/flow-atomic-test-plan.md` (2026-10-18: 103 rows, 0 TODO, four real
findings, all fixed within a day) and `docs/qa/full-app-campaign-2026-10-20.md`.

The executing agent has none of your context. Anything you leave implicit, it will guess,
and the guess is usually the cheap version of the test.

## 1. Before you write

1. **Read what already ran.** Look at `~/qa-runs/*/STATE.md` and `REPORT*.md` (Linux) or
   `C:\Users\Luk\qa-runs\…` (Windows). Collect every FAIL (each becomes a fix-verification
   row once its fix merges), every BLOCKED (each needs a new route around its blocker),
   and every number measured on the wrong build (each needs re-measuring on release).
2. **Read what changed since.** Run `git log --merges --since=<last run>` on master, then
   `git diff --stat` per merge. Each user-visible feature with no device row is a new area.
   Map the paths through the catalog's path index (§13 covers the October features).
3. **Measure the host, don't assume it.** Check `adb devices -l`, both packages'
   `versionName`/`lastUpdateTime`/`pkgFlags`, what's in front (`device.sh fg`), `/dev/kvm`
   (can an emulator run?), Node versions, `sqlite3`, PIL/cv2/ffmpeg. Write the facts into
   the plan's host section with the date.
4. **Check the skill against the code.** Each catalog claim the plan leans on gets a
   `grep` before it goes in. Fix drift in the skill in the same session.

## 2. The skeleton (in this order)

| § | Section | What it must contain |
|---|---|---|
| 0.1 | Mission | the areas in priority order, and why each is there (FAIL → FV, BLOCKED → re-run, new feature, perf gap) |
| 0.2 | Load the skill | how to invoke it **on that agent's host** (slash name, or the `SKILL.md` path), which mode, which references to read in full before the first adb command, and "this plan wins over the skill for this run" |
| 0.3 | Hard rules | no code changes (scripts go in the run folder; a `console.log` probe counts as a change), report don't fix, which device and serial, the foreground check, the tap safe zone, the ratings budget with a number, which rows are ☢ (owner yes per row), restore every setting, no purchases or account actions |
| 0.4 | Host | measured facts and path translations; where reusable instruments from earlier runs live (copy, don't run them in place) |
| 0.5 | Run folder and ledger | path, subfolders, `STATE.md` format, statuses including `STATIC-ONLY`, update after every row, the checkpoint protocol |
| 0.6 | Oracles | a code per defect class, with how it shows in the evidence, **decided before recording** |
| 1 | Instruments | builds and what each is for; the DB oracle; frames; perf; logs; **a positive control for each instrument** |
| 2 | Preflight | atomic P rows, all PASS before anything else: device, builds, bundle proof, baseline DB, a settings snapshot, an inventory with named roles (D-VOC, D-SMALL, …), controls |
| 3+ | Area tables | `ID \| steps \| pass when`; one row per task; exact paths and commands; a numeric n |
| n−1 | Wrap-up | restore and read back every setting, the ratings ledger diff, clean only your own files |
| n | Order and report | the execution order; the report contents (verdict without certification wording, FV table, findings with oracle + rate + confidence + `path:line` + fix direction, per-area tables, perf with n/median/range/floor/build, owner answers, ledger reconciliation, md5 and `FATAL EXCEPTION` audits) |

## 3. Row rules

- **One row, one provable claim.** If "pass when" has two independent clauses that could
  fail separately, split it. Matrices get one sub-row (and one file) per cell.
- **Steps are executable.** Name the screen path, the deep link, the adb command, the SQL.
  Give coordinates only as "from a fresh screenshot of this build".
- **Pass conditions are observable.** Use a count, a DB row, a frame property, or a string
  in a dump. "Works", "smooth" and "looks right" aren't pass conditions; "0 BLANK frames
  in 10 runs" is.
- **Every row names its n.** Use n ≥ 5 for flicker or race rows, ≥ 7 for timings, and n = 3
  where a run costs real ratings.
- **Fix-verification rows reproduce the original trigger**, cite the fix commit **and the
  files it changed**, and run on the release build (dev-client-only caps at PLAUSIBLE).
  The pass condition must not ask for more than the fix changed. If the defect also lives
  somewhere the fix didn't touch, that's a separate row.
- **The ratings log starts at preflight and covers every grade,** and the review
  reconciliation runs **before** wrap-up deletes test cards (deleting a card deletes its
  reviews).
- **Destructive or spending rows are ☢**: `pm clear`, restores, kills during a write, clock
  moves, server-side allowance or quota spends, anything that changes account state. Each
  one needs the owner's yes in chat, per row.
- **Say where a row's oracle can't reach**: a release build has no `run-as`, so use a UI
  oracle or logcat; billing on a sideloaded build; haptics. Pre-mark those `NEEDS-HUMAN`
  with the exact question to ask the owner.
- **Name known non-bugs in the row** that would otherwise be filed (the entry slide on
  focus, the phantom LEARN count, the post-drain streak tick).

## 4. Hand-off

- Put the plan in the app repo at `docs/qa/<name>-<date>.md` (not `docs/reports/`, which
  is read-only history). Don't commit unless the owner asks.
- If the executing agent uses another tool host, make sure it can load the skill (for
  Cursor: `ln -s <skill dir> ~/.cursor/skills/vocacards-app-tester`), and give the owner a
  short starter prompt that names the plan path, the mode, and the first row.
