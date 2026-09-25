# Rulings on the upstream skill

Source: `mobile-app-tester-comprehensive` by abosalehworld-oss
(<https://github.com/abosalehworld-oss/mobile-app-tester-skill>, studied 2026-09-25). It's a
generic, framework-agnostic static-analysis QA skill: a 544-line SKILL.md, 14 phase files
and a 200-bug reference, about 7k lines in all. This file records what VocaCards took from
it, in the ruling format of `docs/design/skill-overrides.md`.

**ADOPT** = kept as is. **TRANSLATE** = kept, but reshaped for this repo. **REJECT** =
dropped, with the reason.

| Upstream rule | Ruling | Why |
|---|---|---|
| Role: senior QA whose job is to find problems, not write code | **ADOPT** | Kept as SKILL.md's opening. |
| Rule 1: citation = path + lines + snippet + why + fix | **ADOPT** | SKILL.md rule 2 and the report format. Also requires the trigger scenario and the user-visible effect, which upstream lacks. |
| Rule 2: 14 mandatory phase gates, no skipping or merging | **REJECT** | It scopes the work by the skill's structure, not by the change. A one-file PR doesn't need 14 phases. Replaced by the four modes and the path index. |
| Rule 3: STOP after every phase for user acknowledgement | **REJECT** | 14 round-trips per review, and a subagent can't get acknowledgement at all. The user is asked once, at the fix-selection point. |
| Rule 4: four-level severity | **TRANSLATE** | Same four levels, redefined as "what a learner loses". Confidence (CONFIRMED / PLAUSIBLE / SUSPECT) is added as a separate axis. |
| Rule 5 + Mechanism 2: cross-reference matrix and file-coverage lists | **TRANSLATE** | Became "Checked and clean" and "Not checked" in the report: honest coverage without a matrix to fill in. |
| Rule 6: framework detection | **REJECT** | The framework is known: Expo SDK 56 / RN 0.85, New Architecture. |
| Rule 7: analysis phases are read-only; fixes in a separate phase | **ADOPT** | SKILL.md rule 1. It's stronger here, because the working tree is shared with live peer sessions. |
| Rule 8: answer in the user's language | **REJECT** | Default Claude behaviour already. The rule was written for Arabic users. |
| Rules 9 and 11: mandatory web search (OWASP, CVEs, store policy) on every run | **TRANSLATE** | Only for store policy in mode D, where the facts really do change. A CVE sweep of a local-first flashcard app on every review is cost with no signal. |
| Rules 10 and 12: fresh-eyes second pass, with proof of re-reading | **TRANSLATE** | Upstream's own evidence was that "a fresh AI agent in a new chat" found what the first pass missed, then it simulated that inside the same context. Here it's a real fresh subagent, and its findings are re-verified. |
| Rule 13: context-decay protection (re-read files, never cite from memory) | **ADOPT** | Folded into "read in this session, not recalled" (rule 2). |
| Rule 14: build and test verification after fixes | **TRANSLATE** | `npm test` + `typecheck` + react-doctor `--scope changed`, with the repo's known env failures called out, plus guard-first fixing from `docs/test-validity-rules.md`. |
| Rule 15 / OT-E: false-positive triage before fixing tool findings; no batch fixes | **ADOPT** | It matters here: react-doctor has five recurring FP idioms whose "fix" introduces a bug, and `mobile_audit.py` has known FPs (`docs/design/skill-overrides.md`). Per-finding web searches are dropped; triage cites the audit docs. |
| Mechanism 1: minimum citation quotas per phase | **REJECT** | Quotas buy padding. Upstream needed a second Rule 15 ("no padding") to fight them. |
| Mechanism 4: later phases must cross-reference earlier ones | **REJECT** | It measures the report's shape, not its truth. "Look one caller out" and "census the class" do the useful part. |
| Phase 11 R1–R4: one fix at a time, before/after, stop per sprint | **TRANSLATE** | One fix at a time in the order the user picks, no sprints. |
| Phase 11 R6: "hacker mindset" re-read of every fix | **TRANSLATE** | Adversarial re-read, aimed at this app's real failure modes: bypass, sibling paths, existing-install data, Classic pixels, native imports, backup compatibility. |
| Phase 12: store and commercial readiness | **TRANSLATE** | Mode D, driven by `docs/known_issues.md` (Convex/Clerk commissioning, RevenueCat keys, signing, 16 KB ELF). |
| Phase 13: mandatory MobSF / apkleaks / nmap, "no tools = fraudulent review" | **REJECT** | Installs and runs third-party attack tooling on every review, and "prove the install failed or you're lying" pressures the agent into installs the user didn't ask for. It also adds nothing a grep for `EXPO_PUBLIC_` secrets doesn't cover for this app. If a real binary audit is ever wanted, it's a separate, user-initiated task. |
| Phase 14: Sentry real-device validation | **REJECT** | The app doesn't use Sentry. Real-device validation is `device-testing.md`, which is built on this project's adb setup, and on asking the user, who holds the phone. |
| Phase 10: health scores, executive summary, sign-off block | **REJECT** | Scores invite false precision (see the MFRI ruling in skill-overrides). The report leads with a ship / fix first / blocked verdict. |
| Tool names `view_file`, `run_command`, `search_web` | **TRANSLATE** | Upstream targets another agent harness. Here it's Read / Bash / Grep / WebSearch. |
| `ref-common-bugs-database.md` (200+ generic bugs) | **TRANSLATE** | RN-relevant items were folded into `generic-mobile-checks.md`. The Flutter, Kotlin and Swift lists are dropped. |
| ALL-CAPS enforcement, "FRAUDULENT/INVALID" framing | **REJECT** | Each rule here carries its reason instead. That generalises better, and it doesn't reward rule-lawyering over judgment. |

## What VocaCards adds that upstream couldn't know

- `hazard-catalog.md`: about 70 defect classes this repo has actually hit, each with a
  code shape to look for, the consequence, and where it's pinned or recorded.
- `device-testing.md`: device roles, peer contention, the foreground check, the long-press
  trap, bundle staleness, and the DB-pull corruption trap.
- Instrument validity (`docs/test-validity-rules.md`): upstream checks the *code*; this
  project has learned to check the *check*.
