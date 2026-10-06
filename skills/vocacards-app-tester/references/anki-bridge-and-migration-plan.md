# Anki bridge and AnkiDroid migration test plan (mode E, Anki campaign)

A campaign plan for the two ways users bring Anki into VocaCards:
- **Desktop bridge:** the `voca_bridge` add-on plus the Convex `bridgeQueue`.
- **Migration from AnkiDroid:** export a file from AnkiDroid, then import it into
  VocaCards.

It uses the same ledger, statuses, definition of done and evidence rules as
`full-device-test-plan.md` §1. Read that first.

## 0. Know what is actually built (do this before writing the ledger)

The design docs disagree with each other. `PLAN-anki-bridge.md` says "one direction,
nothing replayed into Anki", while `PLAN-anki-bridge-handoff.md` documents an armed
replay that wrote 36 revlog rows into Anki. **Establish the feature inventory from the code
at HEAD, not from the docs:**

- **Phone:** `src/bridge/` (`pairing.ts`, `pairingDevice.ts`, `push.ts`, `holding.ts`,
  `rating.ts`, `reviewTime.ts`) and `src/app/settings/anki-bridge.tsx`.
- **Server:** `convex/bridgeQueue.ts`: `publishPair`, `revokePair`, `myPair`,
  `redeemCode`, `push`, `publishHolding`, `holding`. Limits: `MAX_QUEUE_ROWS` 2000,
  `QUEUE_TTL_MS` 30 days, `MAX_PAYLOAD_CHARS` 1024, `MAX_FAILURES` 5.
- **Add-on:** `C:\Users\Luk\Saved Games\vocacards_bridge` (`voca_bridge/`:
  `transport.py`, `safety.py`, `applied_store.py`, `collection_ctx.py`, `ui.py`,
  `xchacha.py`; `config.json`). The deployed copy lives in
  `%APPDATA%\Anki2\addons21\voca_bridge\`.
- **Content Anki → phone:** today this is **file import** (`.apkg` / `.colpkg`) through
  the import screen. If add-on delta extraction (plan phase A.6) isn't in the code, mark
  every delta row **N/A(not built)**, not FAIL.

Write the inventory into `INVENTORY.md`: each capability, the file and line that implements
it, and which test IDs it enables. A row whose capability doesn't exist is `N/A(not built:
<evidence>)`.

## 1. Safety rules specific to Anki

- **Only a dedicated test profile.** Create a fresh Anki profile (`qa-bridge-<date>`)
  through Switch Profile → Add. Never open, sync, arm or edit the `User 1` profile. The
  `phone` profile is an older test profile, so only read it.
- **Never sync to AnkiWeb** from any profile. The bridge is the thing under test, and an
  AnkiWeb sync would upload test data to the owner's account.
- **The add-on's state is shared across profiles.** Before anything else, back up
  `addons21\voca_bridge\` completely (`user_files\` holds the credential and
  `applied_reviews.json`, plus `meta.json`). Restore it at the end, byte for byte, and
  verify with a hash.
- **Deploying a newer add-on is a copy step.** Copy `voca_bridge\*.py` flat into
  `addons21\voca_bridge\`, plus `config.json` and `manifest.json`, but **never**
  `user_files\` or `meta.json`. Record the add-on SHA under test, and check whether the
  deployed copy matches repo HEAD before changing anything.
- **Arm writes (`enable_writes: true`) only in the test profile's collection**, and
  disarm again at the end. Anki takes a forced backup before every write; confirm it
  exists.
- **Oracles on the desktop:**
  - Anki's debug console (Ctrl+Shift+;), for example
    `mw.col.db.scalar("select count() from revlog")` or `mw.col.db.all("select … from
    cards where …")`.
  - Or read `collection.anki2` with sqlite **while Anki is closed**. Anki holds a lock
    while it's open.
  - The add-on writes a session log under the profile folder. Quote its drop and apply
    counts.
- **Oracles on the phone:** the dev client's DB, pulled byte-exact (device-testing §6).
  The release app has no DB access, so use UI counts.
- **Computer use drives Anki Desktop.** Before each click batch, screenshot and confirm
  the Anki window and profile name are what you expect. Never type into any window that
  isn't Anki.

## 2. Unblockers

| ID | Goal | Done when |
|---|---|---|
| AU1 | Inventory written (§0) | `INVENTORY.md` exists, with a file:line per capability |
| AU2 | Test profile created; add-on backed up and hashed | profile name visible in Anki; backup hash recorded |
| AU3 | Add-on under test deployed (repo HEAD), version gate passes | Tools menu shows the VocaCards entry; the SHA recorded |
| AU4 | Phone ready: release app and dev client signed into the SAME test account, both on `dapper-dog-683`. Dev-client Metro started with `APP_VARIANT=development` | both apps show the account; the Metro log has no Linking scheme warning |
| AU5 | Seed: import the same fixture deck into the Anki test profile AND into the phone, so the GUIDs match | the deck exists on both sides; card counts recorded |
| AU6 | AnkiDroid available on the device or emulator. Install it from the Play Store if it's missing (owner-approved for this campaign) | AnkiDroid launches; version recorded |

## 3. Catalog — Desktop bridge

### BP — Pairing

| ID | Test | Pass when |
|---|---|---|
| BP1 | Pair: generate a code on the phone, redeem it in the add-on | both sides show paired; `myPair` exists |
| BP2 | Wrong code, then an expired code (wait out the TTL) | a clear refusal; nothing paired |
| BP3 | "Already paired" on the phone | the copy shown; no second pair |
| BP4 | Code taken (redeem the same code twice) | the second redeem refused ("code-taken"/"not-found") |
| BP5 | Pair while the phone is signed out | "Sign in first"; nothing saved |
| BP6 | Pair while the phone is offline | "Could not reach the server… nothing was saved" |
| BP7 | Revoke from the phone | the add-on's next pull is `unauthorized`, handled with clear UI, no crash |
| BP8 | Revoke from the add-on side, if offered | the phone shows unpaired |
| BP9 | Re-pair after revoke | works; the queue is not replayed twice (the dedupe store holds) |
| BP10 | Two phones (release app and dev client) pair with one add-on, or are refused per the design | documented behaviour, no cross-talk |
| BP11 | Sign out and in on the phone, then account switch | the pairing is per account; no leak across accounts |

### BQ — Push and queue

| ID | Test | Pass when |
|---|---|---|
| BQ1 | Review 20 Anki-sourced cards on the phone → "Send reviews now" | queue depth +20; "Nothing new to send" on the second tap |
| BQ2 | Phone offline while reviewing, then online | queued reviews push once, with no duplicates |
| BQ3 | Reviews of non-Anki (vocab) cards | never pushed |
| BQ4 | Cards from decks the add-on doesn't hold (`holding`) | not pushed, or dropped as unknown; never applied |
| BQ5 | Cap: more than 2000 queued (scripted on the dev client with many reviews, or reason from code if impractical) | the cap holds with clear behaviour; nothing silently lost — record what happens |
| BQ6 | A payload over 1024 chars, if reachable | refused per row; the others go through |

### BR — Replay into Anki (dry run, then armed)

| ID | Test | Pass when |
|---|---|---|
| BR1 | Dry run (disarmed): sync | the session reports would-apply and drop counts; `revlog` count unchanged |
| BR2 | Armed: sync | `revlog` grows by exactly the applied count; durations are the phone's real ones; the forced backup exists |
| BR3 | Re-sync | 0 applied, all `dropped_duplicate` |
| BR4 | A card reviewed in Anki AFTER the phone review | `dropped_superseded` |
| BR5 | A review whose card isn't in the collection | `dropped_unknown_card` |
| BR6 | A review for a deck not ticked in scope | `dropped_out_of_scope`; the unticked deck isn't readable |
| BR7 | Implausible time: the phone or desktop clock is skewed (move the desktop clock via Windows Settings, then restore it) | `dropped_implausible_time` and **not settled**; applies after the clock is fixed |
| BR8 | Rollback: restore Anki from a backup that predates an apply, then sync | the stamped-but-missing rows are detected and the reviews apply again, exactly once |
| BR9 | Corrupt `applied_reviews.json` (on a copy of user_files, in the test profile only) | the add-on refuses to run, with a clear message; restore the original after |
| BR10 | Schema fence: the collection version differs from the bootstrapped one | replay refused, loudly |
| BR11 | `sync_on_open` / `sync_on_close` | a sync runs at those moments; when disarmed it's a dry run |
| BR12 | Anki closed while the phone pushes for a while, then opened | the backlog drains in one session, with correct counts |
| BR13 | Scheduling truth after apply: the Anki card's due, interval and FSRS memory state | consistent with the replayed reviews (record the before and after for 5 cards) |
| BR14 | A card whose note the user edited on the phone (`anki_user_edited`) | its review still applies; content isn't touched by replay |
| BR15 | Learning-step reviews (Again on a new card), then reviews across a day boundary | revlog type and ease correct; no double-count |

### BC — Content Anki → phone (re-import as "sync")

| ID | Test | Pass when |
|---|---|---|
| BC1 | Bootstrap a deck already imported by file | updates, not duplicates (GUID identity) |
| BC2 | Edit a note's field in Anki, re-export, re-import | the phone's content refreshes; scheduling and history are kept |
| BC3 | The same note edited on the phone (`anki_user_edited`), then re-import | the phone edit wins; not clobbered |
| BC4 | Add notes in Anki, re-import | new cards appear as new; existing ones untouched |
| BC5 | Delete notes in Anki, re-import | documented behaviour (kept or removed); no orphaned `card_tag` |
| BC6 | Change a notetype template or CSS in Anki | the template and CSS refresh on the phone even for edited notes (deck-author owned) |
| BC7 | Add a cloze ordinal in Anki (`{{c3::}}`), re-import | the new card appears; existing siblings keep their FSRS state |
| BC8 | Rename a deck, or move cards between subdecks in Anki | the phone's deck tags follow; no duplicates |
| BC9 | Add-on delta extraction (A.6), if built | as BC2–BC8 but through the bridge; otherwise N/A(not built) |

## 4. Catalog — Moving from AnkiDroid

Build a realistic AnkiDroid collection first (AM0). Then export it each way and import it
into VocaCards. Run every row against the **release app** (the users' build) and against the
**dev client** (for DB oracles). "Ground truth" means the values read in AnkiDroid's card
browser/info, or from the exported file opened on the PC.

| ID | Test | Pass when |
|---|---|---|
| AM0 | Build the source collection in AnkiDroid: basic, reversed (2 cards per note), cloze with 3 ordinals, image occlusion, type-in answer, audio `[sound:]`, images, HTML formatting, a field with `&nbsp;`/LaTeX/MathJax, Polish/Japanese/Arabic text, subdecks (`A::B::C`), an empty deck, a suspended card, a buried card, a leech, a filtered deck holding cards, cards in learning, relearning and overdue review, and FSRS on for one preset and SM-2 for another | collection census recorded (notes, cards per state, media count) |
| AM1 | Export the collection as `.colpkg` with media, latest format → import | card count per deck, state, due and FSRS memory equal to the source; media render |
| AM2 | Same, with "support older Anki versions" (legacy format) | same comparison |
| AM3 | Export one deck as `.apkg` with scheduling | same, scoped to the deck |
| AM4 | `.apkg` WITHOUT scheduling | every card new; no stray history |
| AM5 | `.apkg` without media | cards import; media references are handled gracefully (no crash; a visible placeholder) |
| AM6 | Filtered-deck cards | land in their ORIGINAL deck (`odid`), not the filtered deck |
| AM7 | Suspended, buried and leech cards | each state is mapped per the importer's documented rules |
| AM8 | Learning and relearning cards with step position | due and steps preserved, or documented |
| AM9 | Mixed FSRS / SM-2 presets | per-deck presets created; FSRS memory used where present, SM-2 converted per the documented path |
| AM10 | "Import learning progress" OFF (the default) vs ON | OFF: cards new (record it as the open product question); ON: matches AM1 |
| AM11 | The multi-notetype field-mapping prompt | each notetype is prompted with its own fields; the choices persist |
| AM12 | Re-import the same AnkiDroid export after studying on the phone | updates, not duplicates; phone progress kept unless the documented rule says otherwise |
| AM13 | Import a large real-size collection (≥ 20k cards, ≥ 5k media) | completes; time and memory recorded; no "database is locked"; the app stays usable |
| AM14 | Kill the app mid-import (kill loop as in B10) | baseline or full, never partial |
| AM15 | A corrupt or truncated `.colpkg` | clear error; zero partial rows |
| AM16 | Share or "Open with" from AnkiDroid or a file manager into VocaCards | documented: works, or a known gap (no `.apkg` intent filter); record which |
| AM17 | Images and audio after import: render, play, and survive a backup/restore round-trip | media present after the restore |
| AM18 | Cloze and IO rendering: the WebView faces in all four themes and four styles, at font scale 1.3 | readable; no clipped glyphs |
| AM19 | Review history: imported revlog vs VocaCards `reviews` rows and Stats | document what's shown (`.apkg` writes no `reviews` rows — the known open question) |
| AM20 | Onboarding path "Already using Anki?" → import from a fresh install | the import entry reachable; the flow completes |

## 5. Order

AU1–AU6 → BP → AM0 → AM1–AM12 → BQ → BR1 (dry run) → BR2–BR15 (armed, test profile only)
→ BC → AM13–AM20 → restore everything (add-on state hash, clocks, Anki profile left, phone
settings).
