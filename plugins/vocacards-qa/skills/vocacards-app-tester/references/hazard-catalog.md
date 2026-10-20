# VocaCards hazard catalog

Every entry here is a defect class this repo has actually shipped, nearly shipped, or
written a rule against. The generic checklist catches generic bugs. This file catches
the ones that are specific to this app, which a generic reviewer can't know to look
for.

Each hazard gives **Look for** (the code shape), **Why** (what it does to a learner), and
where it's **Pinned** (a guard test) or **Recorded** (the doc or memory that tells the
story). Memory names refer to files in the auto-memory directory. Mirrored copies live in
`docs/claude-code-memory/`.

When an entry and the code disagree, the code and CLAUDE.md win. Report the drift.
Last reconciled against `master @ b1cc09ab` on 2026-10-20.

## Contents

- Path index
- §1 Card writes and Anki notes
- §2 Anki field edit modes
- §3 Migrations and schema
- §4 Backup, export and restore
- §5 Reactive data, queries and the DB connection
- §6 Flow, queue and scheduling
- §7 Theme and style
- §8 Native modules, platform and WebViews
- §9 Auth, account, sync, purchases and network
- §10 Tests and guards
- §11 Don't "fix" (deliberate oddities)
- §12 Release readiness
- §13 Features added in October 2026

## Path index

Map each changed path to the sections to walk. A path can hit several.

| Changed path | Sections |
|---|---|
| `src/lib/store.ts` | 1, 5, 6 |
| `src/lib/cardQuerySql.ts`, `cardFilterSql.ts`, `queueStats.ts` | 5, 6 |
| `src/lib/editableCard.ts`, `src/components/CardEditor.tsx`, `AnkiNoteEditor.tsx`, `StreamCardEditor.tsx`, any `updateCard(` / `updateAnkiNote(` call | 1 |
| `src/lib/ankiFieldModel.ts`, `ankiFormattedField.ts`, `ankiDisplay*` | 2 |
| `src/lib/import/**`, `ImportDeckScreen.tsx`, `src/app/import.tsx`, `csvDeck*`, `src/lib/cardInsertFields.ts` | 1, 4, generic "Input from files" |
| `src/lib/db.ts`, `src/lib/presets/**`, anything with `ALTER TABLE`, `PRAGMA user_version`, `SCHEMA_VERSION` | 3 |
| `src/flow/export.ts`, `src/backup/**`, `src/app/settings/backup.tsx`, restore code | 4, 8 (expo-sharing) |
| `src/app/(tabs)/stream.tsx`, `src/flow/**`, `src/lib/fsrs/**`, `CardStack.tsx`, `FlashCard.tsx`, `useCardSwipeResponder.ts`, `swipePhysics.ts` | 6 |
| `src/lib/themes.ts`, `ThemeProvider.tsx`, `src/lib/gender.ts`, any `color`/`backgroundColor`/`borderColor` or `` `${…accent}` `` | 7 |
| `designStyles(`, `src/lib/design/**`, `styleFonts.ts`, `DirectionProvider.tsx`, `AppText.tsx`, `assets/fonts/**` | 7 |
| `src/components/ClozeFace.tsx`, `ImageOcclusionFace.tsx` (WebViews) | 7, 8 |
| `src/app/_layout.tsx`, `src/app/(tabs)/_layout.tsx`, `package.json` deps, `app.json` / `app.config.js` plugins, a new `import … from "<native pkg>"` | 8 |
| `src/app/sign-in.tsx`, `settings/account.tsx`, `(tabs)/profile.tsx`, `convex/**`, `src/purchases/**`, `src/entitlement/**`, `src/sync/**` | 9 |
| `src/capture/**`, `src/app/inbox.tsx` | 3 (`CAPTURE_COLUMNS`), 9 (Convex probes), generic "Network" |
| `tests/**`, `*.test.ts`, `run-tests.mjs` | 10 |
| `eas.json`, `app.config.js`, `app.json`, `.easignore`, Android build config | 12 |
| `src/lib/dict/**` (catalog, `packManager.ts`), `src/app/create-course.tsx`, `convex/courseMeter.ts`, `courseAllowance.ts` | 5, 9, 13 |
| `src/app/decks/[primaryTag]/practice.tsx`, `modes.tsx`, `src/lib/practiceGames.ts`, `learningModes.ts`, `learningQuiz.ts`, `PracticeGames.tsx` and the game components | 6, 13 |
| `src/lib/holiday*.ts`, `src/app/settings/holiday.tsx`, `src/notifications/**` | 4, 6, 13 |
| `src/chatgpt/**`, `src/app/settings/chatgpt.tsx` | 4, 9, 13 |
| `src/components/QuickBall.tsx`, `src/lib/quickBall.ts` | 7, 13 |

---

## §1 Card writes and Anki notes

- **`updateCard` on an imported Anki card.** *Look for:* an `updateCard(` call that can
  receive a card with `sourceType === "anki"`, or an editor path that routes by
  `cardKind` instead of `sourceType`. *Why:* imported cards render from
  `anki_fields_json`, which `updateCard` doesn't write. The edit is a silent no-op on the
  card face, while the vocab columns drift out of sync. *Recorded:* CLAUDE.md "Two
  card-write paths"; memory anki-note-vs-card-write-paths.
- **Editor mounted directly.** *Look for:* `<AnkiNoteEditor` or `<StreamCardEditor`
  outside `CardEditor.tsx`. The only allowed exception is `add.tsx`'s manual-preview
  step, which is commented in place. *Why:* it bypasses the `sourceType` routing above.
- **Note fan-out.** *Look for:* note-level edits that update one row instead of every
  row sharing `source_id`, or that derive display text from the edited row's ordinal
  instead of each row's own `source_card_ord` (`deriveDisplayPayload`). *Why:* siblings
  of one note legitimately show different text, and a single-row write desyncs them.
- **Cloze ordinal set changed during an edit.** *Look for:* a save path that accepts
  added or removed `{{cN::` ordinals. *Why:* that would create or delete cards and
  orphan FSRS state. v1 blocks the save with explicit copy. Keep it blocked.
- **Re-import clobbers user edits.** *Look for:* changes to `INSERT_CARD_SQL`'s
  `ON CONFLICT` branch, or to `anki_user_edited` / `anki_fields_original_json`. *Why:* a
  re-import must refresh untouched notes and never overwrite edited ones. Templates, CSS
  and mask geometry still refresh unconditionally, because they belong to the deck
  author. *Pinned:* `tests/ankiNoteEditReimport.test.ts`,
  `tests/ankiEditColumnsMigration.test.ts`.
- **Edits strip pack identity. KNOWN OPEN (checked 2026-09-25).** `updateCard` binds
  `lexical_entry_id = ?` and `sense_key = ?` from `updates.lexicalEntryId ?? null`.
  `mapDraftToUpdateArgs` (`src/lib/editableCard.ts`) never supplies either field, and
  all four UI callers (`stream.tsx`, `add.tsx`, `decks/[primaryTag]/cards.tsx`,
  `preview.tsx`) pass its output. So editing a dictionary-backed card NULLs its identity
  and breaks pack dedupe for that card. *Recorded:* memory restore-nulled-pack-identity.
  Report it only if the diff touches this path, and then as "still open".
- **Wrong tag function at review time.** *Look for:* review or update paths calling
  `getPrimaryTagForCard` (the language tag) where `getPrimaryTagForUpdate` (the deck
  tag) is needed. *Why:* an imported card's `primary_tag` is its deck key, and using the
  language tag breaks the daily new-card cap ("resets to 20"). *Recorded:* memory
  imported-card-primary-tag-deck-key.
- **`stripHtml` vs `stripAnkiHtml`.** These are different functions. Using the generic
  one on Anki fields loses Anki-specific markup handling. *Recorded:* memory
  anki-note-vs-card-write-paths.
- **Preset identity.** The global preset has no `config_hash`. Imported presets are keyed
  by `(source_apkg, config_hash)`, so each deck gets its own. *Look for:* dedupe by
  `config_hash` alone, which merges two decks that legitimately share one. *Recorded:*
  memory global-preset-no-config-hash; CLAUDE.md on the preset `UNIQUE` failure.
- **Library import rows hidden by the onboarding gates** (2026-09-26; a fix was chosen
  and staged that day, so check master before reporting it). The Library's IMPORT rows
  call `pickFile` in place. They don't route to `/import`, so grepping for `/import` finds
  only `EmptyFlowView` and gives the false "unreachable" conclusion a Codex run once
  reported. The rows are gated by the `library.import*Enabled` settings (`?? true`).
  Welcome wrote them from `libraryImportGatesFromInterests`
  (`src/onboarding/getStartedOptions.ts`). Its default ticks don't include "file", so the
  file row started hidden. The way back, `/settings/caught-up`, sits behind the
  Power-mode + signed-in gate. The staged fix stops Welcome writing the file gate.
  **Still open:** installs that already stored `false` stay hidden. *Look for:* any gate
  that hides a core action with no visible way back. In device tests, the dev-client link
  `vocacards-dev:///import?uri=…&autoImport=1` drives an import without the picker.
- **Anki import drops history by default. OPEN PRODUCT QUESTION (2026-09-26); don't
  report it as a new bug.**
  - The import screen starts with "Import learning progress" **off**
    (`src/lib/importDeckState.ts:111`), while the parser's own default is `true`
    (`src/lib/apkgParser.ts:1821`). There's no DECISIONS entry; "off" came across
    verbatim in the #80 refactor. The deep-link auto-import can never turn it on.
  - Even with it on, `.apkg` import replays revlog into FSRS scheduling but writes no
    `reviews` rows, so Stats and the streak don't count imported history. Only the JSON
    backup path writes `reviews`.
  - Onboarding promises that an import "keeps the review history you have already built
    up".
  - *Look for:* a change to either default, or to what import writes, and flag the
    mismatch.
- **Unsaved-edit guard on 1 of 4 editor mounts (checked 2026-09-26, master
  `f83bcbef`).** Only `decks/[primaryTag]/cards.tsx` passes `onDirtyChange` and adds a
  `beforeRemove` listener. `preview.tsx:831`, `(tabs)/stream.tsx:1935` and `add.tsx:843`
  mount `CardEditor` without it, so Back or Cancel silently discards a typed edit (a
  device run confirmed this on `preview.tsx`). *Look for:* any new `<CardEditor` mount
  without the dirty guard.

## §2 Anki field edit modes

Source: CLAUDE.md "Field edit modes". This area has fixed the same bug class three
times. Read the code, not just the diff.

- **A friendly mode that doesn't round-trip.** *Look for:* a change that lets more shapes
  into `cloze`/`media`/`plain`/`formatted`. *Why:* the ordering in `classifyField` is a
  safety ordering. Only shapes that round-trip losslessly get a friendly editor.
  Everything else stays `rich` (raw HTML). Ask for the property test that proves the
  round-trip.
- **Blacklist logic in the formatted parser.** It must stay a whitelist. Unknown tags,
  unknown attributes, unrecognised CSS, malformed nesting, depth over 5, and
  `<div>`/`<p>` all mean "stay `rich`".
- **Semantic text tokens.** Anything with meaning that isn't tag-shaped (`[sound:…]`,
  LaTeX, MathJax, TTS, replay hooks, type-answer markers) must be covered by
  `SEMANTIC_TEXT_TOKEN_PATTERNS`. When one new token turns up, census the whole class
  before patching the one you found.
- **Anchor glyphs.** Each anchor must project exactly **one UTF-16 code unit** (`♪`,
  `▣`). An astral glyph (`🔊`) is two units and can be bisected, and the property test
  fails with a lone surrogate. Anchors are identified by token position, never by glyph.
- **Unlifted media inside a friendly editor.** The semantic-token guard must run on the
  *editable surface*, not the raw body. A `[sound:x` with no `]` must still be refused.
- **ATTACH-LEFT split.** The suffix clamp in the text diff and the run-boundary join are
  one rule. A change to one without the other, or a test for anchors placed outside the
  shared test block, is a finding.
- **Entity handling.** Only `&nbsp;` is decoded. Blanket re-encoding rewrites fields
  that were never encoded.

## §3 Migrations and schema

Source: CLAUDE.md "One-shot data migrations" (read it in full before judging a
migration).

- **State-writing statement in the bare `runMigrations` body.** *Look for:* any
  `UPDATE`/`DELETE` touching `cards.state`, `learning_steps`, `due_at`, `stability`,
  `difficulty`, `reps`, `lapses`, `primary_tag` (or other live state) that isn't behind
  its own `user_prefs` marker. *Why:* `SCHEMA_VERSION` is an equality check
  (`src/lib/db.ts`, `getDb`). Any future bump re-runs the whole body against live data,
  and normal use can put rows back inside a `WHERE` that looked historical. The worked
  example: Rating Hard at learning step 0 fell inside a bare-body `WHERE`, so every bump
  would have advanced those cards a step. *Copy:* `backfillSourceDeckTagLinks`.
  🔴 when it touches FSRS state.
- **`SCHEMA_VERSION` bump.** Treat it as a change to every statement in the body.
  **Open item that blocks any bump:** `UPDATE dailyStats SET activity = reviews WHERE
  activity = 0 AND reviews > 0` has a state guard. Nobody has yet determined whether a
  live row can re-enter it. A diff that bumps the version without settling this is a
  finding.
- **Additive column in the wrong place.** *Look for:* a new column added to a list
  inside `runMigrations`. *Why:* it reaches only installs whose `user_version` differs.
  Installs already at the current version never get it and throw `no such column`. It
  belongs in the unconditional module-scope path (`CAPTURE_COLUMNS` pattern). A version
  bump is the wrong tool for this.
- **A "separate" version counter stored somewhere shared.** Check where a counter
  actually lives. The preset migrations once shared `PRAGMA user_version` with the
  schema, got rewound by every bump, and killed DB init. They now use
  `user_prefs["migration::preset_config_hash_version"]`.
- **Deleted vs gated.** Prefer deleting a spent migration to gating it. A gate that "runs
  one more time" on existing installs is the same bug.

## §4 Backup, export and restore

- **A new `cards` column that export or restore doesn't carry.** *Look for:* a schema
  addition with no matching change in export/restore, or any hand-written column list.
  *Why:* the 2026-09-14 restore bound a hand-written `CARD_COLUMNS` that omitted six
  columns, which NULLed pack identity across a whole collection. The next backup
  faithfully preserved the loss. Restore now reads live `PRAGMA table_info(cards)`
  (`a3338ce`). *Pinned:* `tests/backupCardColumnRoundTrip.test.ts`. 🔴
- **Anki edit columns dropped from a backup.** `anki_fields_original_json` and
  `anki_user_edited` must survive a round-trip. Otherwise edited notes are exposed to
  re-import clobbering again. *Recorded:* CLAUDE.md "Two card-write paths".
- **`card_tag` rebuilt from `cards.tags`.** `card_tag` isn't reconstructable from
  `cards.tags`. The rebuild fallback is a lossy superset. Backups carry `card_tag ⋈ tag`
  verbatim. *Recorded:* memory backup-omits-tag-tables.
- **Presets and dangling `preset_id`.** A restore carries source-device preset ids.
  Dangling bindings must be cleared in `getDb`, and the resolver must fall back to
  global. v5+ backups carry non-global presets. *Recorded:* memory
  restore-dangling-preset-id.
- **Performance shape.** Export is SQLite round-trip bound: `card_tag` at ~310k rows in
  50-row chunks was 7,287 trips. Restore is `TextDecoder`-bound (~1.4 MB/s polyfill),
  not `JSON.parse`. Media cost is per-request overhead. *Look for:* changes that
  multiply round-trips or per-file requests. *Recorded:* memories
  export-is-roundtrip-bound and restore-is-decode-bound.
- **Local wipe without a JS reload.** Account delete and full reset must reload the
  bundle. Theme and settings are in-memory mirrors above the navigator, and
  `router.replace` won't reset them. *Recorded:* memory local-wipe-needs-js-reload.

## §5 Reactive data, queries and the DB connection

- **A mutation with no notify.** *Look for:* a write in `store.ts` that doesn't bump the
  revision (`notifyCardDataChanged`, or the coalesced `notifyCardDataChangedSoon` on the
  review hot path), or an outside-`store.ts` write with no `notifyTagsChanged()`.
  *Why:* the UI stays stale until something unrelated refreshes it.
  *Confirmed instance (2026-09-26, fixed: `importFromParsed` now ends with
  `notifyTagsChanged()`):* Import JSON showed a just-restored deck only after a relaunch. The Drive restore masks the same gap with
  `reloadApp()`. **A JS reload in one caller can hide a missing notify in a shared
  function.** Check every caller, not just the one you tested.
- **A notify storm.** *Look for:* `notifyTagsChanged()` inside a loop or per-row during
  import or merge. *Why:* each notify triggers a read storm (305 query batches in 146 s
  during one import). That storm, not the writes, is what contends for the DB and
  produces "database is locked". `installWriteGate` serialises writes and can't help
  here. *Recorded:* memory course-create-db-lock-retry.
- **A forced-card pin without the filter.** In `fetchCards`/`fetchQueueStats`, the
  `forcedCardId` pin must keep `AND ${filterClause}`. Otherwise a just-added card leaks
  under every tag chip. *Recorded:* memory forced-card-pin-must-scope-filter.
- **Placeholder and param mismatch.** *Look for:* SQL whose `?` count can differ from its
  params array, especially when a clause is added conditionally (paused exclusion). The
  worked example threw inside `fetchQueueStats`, and `useQueueStats` swallowed the error
  to `{0,0,0}`. The fix was `buildQueueCountsQuery`. *Recorded:* memory
  queuestats-paused-param-mismatch.
- **Errors swallowed to plausible values.** *Look for:* `.catch(() => {})`, a
  `catch { return 0 }`, or a hook that keeps the last good value on failure. There are
  about 100 `.catch(() => {})` in `src`, and most are fine fire-and-forget. The question
  is whether a failure at *this* site leaves persistent wrong state with no signal.
- **Stale reads (cause found and fixed 2026-10-20, #349 and #350).** Writes commit on
  their own connection (`withExclusiveTransactionAsync`). SQLite keeps one read snapshot
  per connection while **any** statement on it is active. So a burst of overlapping reads
  on the shared connection that straddles a commit serves the pre-commit snapshot, and
  nothing re-reads once it drains. Tags were fixed in #349 and card data in #350:
  `db.ts` counts shared statements (`trackSharedStatements`, `whenSharedReadsIdle`), and
  `afterSharedReadsSettle` schedules one trailing re-read per target (300 ms, then
  idle-or-2 s). *Look for:* a new notifier or cache that reads after a write but doesn't
  route through `notifyTagsChanged`/`notifyCardDataChanged` (so it gets no settled
  re-read); a settled refresh that re-arms itself (a loop); a hot-path change that adds
  more than the one extra refresh per burst. *Pinned:* `tests/sharedReadsIdle.test.ts`,
  `tests/libraryRefreshAfterCourse.test.ts`, `tests/cardDataSettledRefresh.test.ts`.
  *Recorded:* memory app-reads-stale-sqlite-snapshot.
- **Round-trips, not SQL time.** Each JS↔native SQLite hop costs ~29 ms on device, and
  query time is noise next to that. *Look for:* new sequential awaits on the review hot
  path (`recordReview*`), per-row queries in loops, or chunk sizes that multiply trips.
  *Recorded:* memory swipe-perf-measurement-toolkit.
- **A correlated or `LOWER()` visibility gate.** The Flow visibility gate is parametric
  (graduating tags passed in) with a covering index. The old correlated `LOWER()` gate
  cost ~100 ms per query. *Recorded:* memory flow-gate-perf.

## §6 Flow, queue and scheduling

- **Ephemeral Stream state lost on the `/add` round-trip.** Returning from `/add`
  remounts Stream, and expo-router briefly renders two Stream instances. State that must
  survive (a special session, a just-added card) needs a module-level handoff slot like
  `addedCardHandoff`, not `useState`. *Recorded:* memories
  stream-remounts-on-add-roundtrip and add-roundtrip-query-storm.
- **Learn-more rebuilt as cap arithmetic.** Extras are *dealt* via
  `fetchLearnAheadNewCards` as a `learnMore` special session. Three
  `extraNewCards`-arithmetic variants failed. *Recorded:* memory learn-more-dealt-session.
- **A special session that outlives its context.** Changing the deck filter must end a
  special session (#179). *Look for:* new session entry or exit paths that skip that
  reset.
- **The streak gate strands "Loading…" (historical).** `streakSyncPending` no longer
  exists (0 references on 2026-10-20); the streak number may tick up a few hundred ms
  after the caught-up page appears, and that's intended. *Look for:* any new gate that
  holds the caught-up page or a loader on an async streak read. *Recorded:* memory
  streak-sync-pending-strand-hasdue.
- **Counter vs servable queue.** The LEARN header counts Again-rated cards ~10 min before
  they're servable, and the same term inflates `dueTodayCount`. It's known, so don't
  re-report it. Do report new code that trusts the counter as "a card is available".
  *Recorded:* memory learn-counter-overstates-servable-queue.
- **An invisible card vs the caught-up page.** A nonzero header over the caught-up body
  means a card is mounted at opacity 0, not that the session ended (`showingCaughtUpBody`
  requires `!shouldRenderCardStack`). *Recorded:* memory
  diagnosing-invisible-card-on-flow.
- **FSRS config.** Preset learning and relearning steps reach `getFsrs`, and load
  balancing runs (`f6cf1dd`, with a 90-day forecast in `fc01680`). `toFsrsCard` still
  passes `scheduled_days: 0` to ts-fsrs. That's fine: the granted interval is read from
  `card.scheduled_days`, not `log.scheduled_days` (comment at `src/flow/scheduler.ts`
  ~156). *Look for:* code that reads `log.scheduled_days` again. *Recorded:* memory
  fsrs-config-never-reaches-generatorparameters.
- **`mastery_score` has two meanings.** Sync replay and warm-start write retrievability
  (≈1.0 right after a review), while live review adds +0.1. Code that compares or
  thresholds it has to know which one it's reading. *Recorded:* memory
  mastery-score-two-semantics.
- **Time-budget throttling reintroduced.** It was removed on purpose: new cards deliver
  the full per-deck daily cap. *Recorded:* memory time-budget-removed.
- **Reviews/day cap scope.** `maxReviewsPerDay` caps only due cards already in FSRS
  Review state, and Learning/Relearning bypass it (`docs/known_issues.md`).
- **Flow geometry and motion: no longer frozen (2026-09-30), but measured.** The Quiet
  Study board reshaped the header, card faces, grading and dock (CLAUDE.md, Styles). Change
  them on purpose, in Papier Light and Noir, on the POCO. The swipe physics
  (`useCardSwipeResponder`, `swipePhysics.ts`) are still load-bearing: measure before
  moving them. The swipe threshold has one home, `swipePhysics.ts`.
  *Pinned:* `tests/swipeThresholdSingleSource.test.ts`,
  `tests/geometryConstantRegistry.test.ts`, `tests/geometryLaws.test.ts`.
- **Stream `freezeOnBlur`.** It's `false` on purpose: a frozen tab blanked WebView cards
  for ~0.5 s on re-entry. The card-entry slide replays on every entry, also on purpose.
  *Recorded:* memory tab-switch-detach-couples-freeze.
- **Reference identity in effect deps.** A fresh object per render in a deps list (the
  `useTabBar()` case) fired `navigation.setOptions` on every Flow render, mid-swipe, for
  ~4 pp of jank. *Recorded:* test-validity-rules, Appendix "Shape B".

## §7 Theme and style

Sources: CLAUDE.md "Theming" and "Styles"; `docs/theme-binding-rubric.md`;
`docs/design/skill-overrides.md`.

- **A hand-computed per-mode value.** *Look for:* `mode === "dark" ? … : …` colour
  literals, or any colour not bound to a `theme.color.*` token. *Why:* mode inversion is
  the central hazard. A value tuned for one palette breaks in the other three. Check all
  four palettes (Papier Light, Papier Noir, Carta, Goldleaf).
- **A chrome wash on `accent` instead of `tint`.** *Look for:* `` `${accent}15` `` fills or
  `` `${accent}33` `` hairlines on chrome. *Why:* that is what made Papier Noir read green
  everywhere. Chrome washes bind `tint`. Solid `accent` is for buttons, icons, the mastery
  ring and selection cues. A new deliberate accent wash has to be added to the count in
  `tests/noirNeutralChrome.test.ts`. If it isn't, that's a finding.
- **Pill and chip moved apart.** The label pill and the selected chip are one decision.
  The dark palettes use a 0.15 wash with width `0`, not `null` (`null` puts a solid
  hairline back). Noir's hue is `textPrimary`, Goldleaf's is its accent. *Pinned:*
  `tests/noirNeutralChrome.test.ts`.
- **Functional colour treated as chrome.** Gender (`src/lib/gender.ts`) and queue-state
  (`queueNew`/`queueLearn`/`queueReview`) are functional axes with per-mode values. Don't
  replace them with accent or tint.
- **A numeric literal not routed through `d`.** In a converted file, every
  type/space/radius literal goes through `designStyles((d) => …)`. `tokenize.mjs` reports
  what's left. Under Classic every scale is the identity, so routing can't change Classic.
  A bare literal silently ignores Airy, Compact and Book.
- **Geometry routed through `d`.** The opposite error. Circles and capsules (radius ≥
  half a fixed side), drawn glyphs, chart geometry, the dock, and anything a hit slop or
  measurement depends on stay literal. Label pills are style: `d.radius(999)`.
- **Text in a fixed-size box.** Badges, circles, steppers and the pause chip need
  `marginVertical: -10` on the Text, with any optical nudge added to the top value, and
  no fixed `lineHeight`. *Why:* at large system text, and especially in Book (Charis's
  line box is ~1.7 em), the glyph sits low. This was fixed at ten sites found by census.
- **Font faces.** Faces load at runtime (`styleFonts.ts`) and first paint is held until
  they register, with a Classic fallback after 3 s. Compact's IPA must use its `ipa`
  faces (Plex has no IPA). WebView `webFontCss` rules sit flush against `</style>` so a
  Classic document stays byte-identical.
- **Largest font scale.** Chrome must survive `font_scale` 1.3 and the device's largest
  setting with no new overflow compared to baseline (`docs/design/skill-overrides.md`).
- **Proof standard.** A style conversion is proven pixel-identical under Classic
  (HEAD-vs-change captures, cold relaunch each side) and eyeballed under the other three
  styles (`docs/design/phase1-tokenization-log.md`). A claim of "no visual change" with
  no capture is PLAUSIBLE at most.

## §8 Native modules, platform and WebViews

- **Top-level import of a native-backed package.** *Look for:* `import … from
  "<pkg>"` where the package calls `requireNativeModule` at module scope, in any file a UI
  surface imports. *Why:* on a build that predates the dependency (every iOS dev client
  until an EAS rebuild) the module throws while evaluating. Render is blocked, and
  expo-router then dies reading `ErrorBoundary`. Use a lazy `require()` at the call site,
  plus a source assertion (`doesNotMatch` the import, `match` the require). Known sites:
  `expo-navigation-bar` (`_layout.tsx`), `react-native-purchases`
  (`purchasesBridge.tsx`), `expo-sharing` (`src/flow/export.ts`). *Pinned:*
  `tests/buildInfoLazyRequire.test.ts` and the owning tests. 🔴 for anything in the root
  layout.
- **A new native dependency or config plugin.** It needs a native rebuild. OAuth
  redirect schemes (Drive's reversed client id) fail as "can't connect" on a stale APK.
  *Recorded:* memory drive-connect-needs-native-rebuild.
- **WebView cards.** Cloze and IO faces need `androidLayerType="hardware"`. Without it,
  swipes are choppy because of render-thread recompositing, and JS tuning has no effect.
  *Recorded:* memory webview-swipe-jank-android-layer.
- **Edge-to-edge keyboard.** `KeyboardAvoidingView behavior="height"` never resets on
  edge-to-edge Android. Don't drive layout from keyboard geometry. *Recorded:* memory
  addcard-preview-keyboard-resize.
- **System-bar overlays.** The status and nav-bar fills are root overlays in
  `_layout.tsx`, and Stream deliberately lets the card float over both. Changing their
  zIndex or route gating affects every screen.
- **New Architecture.** Don't propose `newArchEnabled: false`: the solana codegen and KSP
  block an old-arch build. *Recorded:* memory newarch-nav-regression.
- **RTL and start/end.** Use `start`/`end`, not `left`/`right`, where direction matters.
  Some tests assert this at the source level.

## §9 Auth, account, sync, purchases and network

- **Offline sign-out.** Clerk's `signOut()` clears the in-memory session before the
  network revoke and doesn't roll back. Offline is blocked by an `expo-network`
  pre-check in `profile.tsx`. *Look for:* new sign-out entry points without it.
  *Recorded:* memory clerk-signout-offline-halfstate.
- **Account deletion.** `accountDeletion:purgeSubjectDataBatch` destroys every
  identity-linked row. It's the account-shred path. Never run it to "check" something.
  Use the narrow `devMaintenance:census*` / `purge*` probes. 🔴 if any test, script or
  dev screen calls it casually.
- **Entitlement precedence.** `DEV_ENTITLEMENT_OVERRIDE` beats every user's real claim
  (F-004), and production builds reached the dev deployment until 2026-08-03. *Pinned:*
  `tests/revenuecatClaimProjection.test.ts`, `tests/buildProfileTargets.test.ts`.
- **Convex identity checks fail closed.** Every identity-reading entry point refuses on
  a null identity (`docs/known_issues.md` table). *Look for:* a new Convex function that
  reads user data without the same refusal.
- **Probe hygiene.** REST probes must check the HTTP status, because a 401 body parsed as
  "no entitlements" was reported three times as "the purchase never happened". Convex MCP
  returns an empty page for a non-existent table (`slots` vs `deviceSlots`). List the
  tables first. `npx convex env list` prints live secrets, so treat that transcript as
  secret-bearing.
- **Wiktionary.** It returns 403 from Android without a `User-Agent`. Always send one.
- **`EXPO_PUBLIC_*` is public.** Anything with that prefix is inlined into the bundle.
  A secret there is a 🔴 finding.

## §10 Tests and guards

Source: `docs/test-validity-rules.md`. Apply these when a diff adds or changes a test.

- **A test that can't fail.** Every value it touches is defined in the test file (rule
  1). Name the source symbol it would break on. If you can't, it's a specification, and
  must say so in a comment (rule 2).
- **Proxy assertions.** It asserts *presence* (a name, an import, a symbol in the file)
  where it means *use* (this value, at this call). Write the mutation that keeps the
  assertion true and breaks the behaviour. If you can, it's a proxy (rule 8).
- **Over-specified source guards.** Line adjacency or exact formatting. These break on
  correct changes, as `waitFor={panRef}` between two props did. Ask whether the guard is
  over-specified before assuming the code is wrong (memory run-npm-test-before-commit).
- **Geometry in the suite.** The test renderer has no Yoga pass. `onLayout` never fires,
  so a render test at 300 dp and at 1280 dp gives identical output. Visual correctness,
  gesture feel, IME, frame rate and WebView faces are device criteria (rule 4).
- **Discovery.** `run-tests.mjs` auto-discovers `*.test.ts` / `*-test.ts` under `src/`
  and `tests/`. A new test needs no registration, but a test named any other way never
  runs.

## §11 Don't "fix" (deliberate oddities)

Report none of these as bugs. If a diff "fixes" one, that's the finding.

- `CardEditor` falls back to `StreamCardEditor` for an anki row with no `source_id` (a
  `__DEV__` warning, not a throw).
- The react-doctor false-positive idioms in `docs/react-doctor/react-doctor-audit.md`:
  the `beforeRemove` cast-alias cleanup, the load flag in async data effects, timer-ref
  cleanup reads, lazy-init `??=` refs, and dynamic `obj[field]` reads already covered.
- Imports writing `lang: ""` (csv and apkg): DECIDED 2026-09-25 to leave as is, because a
  re-import heals it (memory import-writes-empty-lang).
- `formatted` mode can't *apply* formatting. It's preserve-only by design.
- Only `&nbsp;` is decoded among entities.
- `docs/`, `tests/` and `e2e/` excluded by `.easignore` but tracked in git.
- Stream's `freezeOnBlur: false` and the card-entry slide replaying on every entry.
- `useQueueStats` keeping its last good value on failure is intentional. Hiding a
  *thrown query* behind it is not (§5).
- Known dev-client-only crashes, which are not app code: the `onUserLeaveHint` NPE, and
  the Fabric `findNextFocusableElement` SIGSEGV on reload.

## §12 Release readiness (mode D)

Read `docs/known_issues.md` in full. Its status lines move. Then check:

- **Deployment pointers.** Production `eas.json` pins a prod Convex URL and a `pk_live_`
  Clerk key, both together (`tests/buildProfileTargets.test.ts`). Is the throwaway-build
  auth check (commissioning step 5) done yet? Is `vocacards://sso-callback` on the
  production Clerk allowlist?
- **The one-way door.** DEKs live in Clerk `privateMetadata` and don't migrate between
  instances. Encrypted backups made against the test instance become unreadable at
  cutover. The Clerk production cutover must land before Play launch.
- **RevenueCat.** Is there an Android key on `production`? An iOS key anywhere? A
  `test_` key is rejected outside `__DEV__` by design. Client purchase, restore and
  identity binding are unverified on both platforms until a sandbox run is recorded.
- **Signing.** Local Android release builds are signed with `signingConfigs.debug`
  (fine for `adb install -r` over a debug build). A Play upload needs the real upload
  key; see `docs/android-build.md`. Verify with `apksigner verify --print-certs`.
- **Native checks.** `scripts/check-elf-16kb.mjs` (16 KB page alignment) and
  `scripts/mlkit-apk-size.mjs`.
- **Migrations.** Is there a `SCHEMA_VERSION` bump in the release range? Then §3's open
  item must be settled first.
- **Lazy requires.** A native package added since the last store or dev-client build is
  a render-blocker on old clients (§8).
- **Store policy.** Target API level, data-safety form and account-deletion disclosure
  (`tests/accountDeleteDisclosure.test.ts`) change over time. Search the web for the
  current Google Play and App Store requirements and cite the URLs. Don't answer this
  item from memory.
- **Fresh-eyes pass.** Always, in this mode (SKILL.md §4 step 6).

## §13 Features added in October 2026

None of these had a device run before the 2026-10-20 campaign
(`docs/qa/full-app-campaign-2026-10-20.md` in the app repo). Where that campaign has run,
its ledger in `~/qa-runs/2026-10-20-full-app/` is the record.

- **Practice games are never graded.** `practice.tsx` hosts 11 games (`match`, `sprint`,
  `gap`, `tiles`, `builder`, `dictation`, `listen`, `loop`, `tough`, `aspect`,
  `prefixes`). `practiceGames.ts` is pure and reads `lapses`/`dueAt` but "never written
  here". *Look for:* any `recordReview*`, `reviews` insert or FSRS column write reachable
  from a game, or from the Flow's Practice/Peek sessions. *Oracle:* `reviews` count, plus
  three cards' FSRS columns, before and after. The `game` param is checked against own
  keys only (`game=constructor` must fall back to Match board).
- **Learning modes and Meet first.** Quiz, Listen first, Second chance, Recall it, Word in
  context, Write it (`learningModes.ts`, `modes.tsx`). Quiz right writes 3 and wrong writes
  1. A new word is shown, not quizzed, on its first showing (#326). A Second-chance retry
  comes back 3 cards later and **must not** write a second review. *Look for:* a retry
  path that calls the review writer. A TTS mode must handle a rejected voice lookup
  (`getAvailableVoicesAsync`, "Unable to get voices"). `182514ef` fixed it inside
  `isLanguageAvailable`, and `speak` has its own `try`. `initTts` and `listVoicesFor`
  (`src/lib/tts.ts`) still reject: census their callers for the same uncaught rejection.
- **Holiday mode (Pro).** `holiday.ts` (pure) and `holidayStore.ts` (one
  `user_prefs["flow.holiday"]` row, **cached in memory**). Flow serves nothing, the streak
  skips the days, and reminders are quiet. *Look for:* (a) a session path (Learn more,
  Practice, Peek) that serves or **persists** during a holiday; (b) the file comment says
  device-local and "not synced", but `flow.holiday` is **not** on
  `IMPORT_PREF_DENYLIST_PREFIXES` (`src/flow/export.ts`), so a backup carries it to
  another device, and an Import JSON without a JS reload leaves the in-memory cache stale
  (PLAUSIBLE, unverified on 2026-10-20); (c) day keys computed in local time instead of the
  logical day (`getLogicalDateKey` with `dayRolloverHour`/timezone).
- **Evening streak reminder.** `planStreakReminder` mirrors `evaluateStreak`. It returns
  null when today is done or the streak isn't savable, and skips holiday days. *Look for:*
  copy that promises a streak the rules would break; scheduling that ignores the holiday.
- **Dictionary packs from the CDN catalog.** `catalog.ts` applies the AsyncStorage cache,
  then fetches, and never throws. `packManager.ts` downloads, then checks the size, then
  SHA-256, then ungzips **the whole pack in memory** (~45 MB peak for es-en), stages it,
  moves it into place and records the version. A `finally` removes the staging files.
  *Look for:* a version recorded before the move (a pack that claims to be installed but
  is missing); a kill between the move and `setInstalledDictVersion` (a file with no version,
  so a re-download); a new pack big enough to OOM a low-end device.
- **Course allowance (server-side).** `convex/courseMeter.ts`: 500 distinct words in the
  first month after signup, then 200 a month (UTC anniversaries), Pro unlimited, and word
  IDs already used this period are free on retry. It's authorized **before** the local
  writes. *Look for:* a client path that writes the deck before `authorize` returns; a
  retry that sends new word IDs for the same words (double charge); entitlement read from
  anything other than the JWT claim. Device tests spend the account's real allowance, so
  they need the owner's yes.
- **ChatGPT deck delivery.** `src/chatgpt/**`; backups rebase ChatGPT media
  (`rebaseChatgptMedia`) and restore `chatgpt.deck.*` prefs while dropping cursors,
  receipts and acks. *Look for:* a re-delivery that resets study progress on existing card
  ids; an offline Receive with no error (the Redmi run saw a spinner for more than 15 s
  before the fix); a conflict resolution that loses the local edit.
- **Quick-ball navigation.** An alternative to the dock (`QuickBall.tsx`). *Look for:* the
  ball covering the grading edges, the caught-up buttons or a pay bar; a ball that eats a
  card gesture; a position that doesn't persist.
