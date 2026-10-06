# Generic mobile checks (React Native / Expo)

This is the upstream skill's phases 2–9 and its React Native top-20 bug list, cut down to
what applies to this app. Use it on *changed code*, after the hazard catalog. Each item
is a question. Skip anything that doesn't apply to the diff. It's a prompt for your eyes,
not a gate to fill in.

Where an item has a project-specific form, the catalog section is noted and that section
takes precedence.

## Lifecycle and effects

- Does every `useEffect` that subscribes, listens, sets a timer or starts an animation
  return a cleanup? (Check react-doctor's FP list before flagging a cast-aliased
  `beforeRemove` listener.)
- Can async work set state after unmount or after its inputs changed? Look for a missing
  cancelled flag, or a stale closure over an old id.
- Are effect deps stable references? A fresh object or array per render in deps re-fires
  the effect every render (catalog §6, "Reference identity").
- AppState: does anything that must pause in the background (timers, audio, sync) handle
  `background` → `active`, including the day rollover while backgrounded?

## Rendering and lists

- Lists: `FlatList`/`reorderable-list` with stable `keyExtractor`, no `FlatList` inside a
  same-direction `ScrollView`, no index keys on reorderable data.
- Inline style objects or closures in a hot list or the Flow card cause per-render
  allocation. They matter on the Flow and in big deck lists, not on Settings.
- Heavy work in render (sorting or filtering thousands of cards) should be memoised or
  moved into SQL. Collections run to ~45k cards and ~310k `card_tag` rows.
- Images: `expo-image` with a size, or intrinsic dimensions for media on cards. Check for
  unbounded decode of large Anki media.

## Error handling and crash paths

- Is there a route-level `ErrorBoundary` where a thrown render would otherwise blank the
  app? (expo-router reads `ErrorBoundary` off the module; catalog §8.)
- Does a `catch` distinguish "failed" from "empty"? Returning `[]`, `0` or `null` on error
  hides failures (catalog §5).
- Null and undefined from SQLite: nullable columns, `getFirstAsync` returning `null`, and
  JSON columns that may be `""` or malformed (`anki_fields_json`, `meanings`).
- User-facing error text: plain language, and it says what the user can do. No raw
  `Error.message` from the native layer.
- `console.log` isn't a crash report. Only `console.error` reaches logcat.

## Input from files and the network

- **Imports** (`.apkg`, `.colpkg`, CSV, backups) are untrusted input. Check for malformed
  archives, missing media, huge fields, zip entries with `../` paths, non-UTF-8 CSV, BOMs,
  duplicate GUIDs, and a deck with zero notes. Does a failed import leave partial rows
  behind? Is it resumable or rolled back?
- **Network** (dictionary packs, Wiktionary, Drive, Convex, Gemini capture): timeouts,
  offline behaviour (`expo-network`), retries that don't duplicate writes, and a status
  code checked before the body is parsed. `User-Agent` for Wiktionary.
- Downloads: integrity checked (pack SHA-256 manifests), and partial files cleaned up.

## Data and state

- Single source of truth: is a value duplicated into React state and then drifting from
  the DB? (The streak divergence was a per-hook copy; the fix was the `streakStore`
  pub/sub.)
- Races: two writers on the same row (sync replay vs live review, import vs review), a
  double-tap submitting twice, a navigation that fires twice.
- AsyncStorage (`src/storage/settings.ts`) holds settings, never secrets. Secrets and
  tokens belong in `expo-secure-store`.
- Dates: day rollover hour, timezone (`@date-fns/tz`), DST transitions, "today" computed
  in one place (`dayBoundary`). Check any `new Date()` arithmetic done by hand.
- Reachability: is every feature reachable once the user has data, in every mode (Simple
  and Power, signed in and out)? Look for entry points that live only in an empty-state
  view, and for settings gates that hide an action with no visible way back (the Library
  import rows, catalog §1). Census entry points by *handler* (`pickFile`,
  `router.push`), not by route string: an in-place action never mentions its route.

## Platform

- `Platform.OS` branches: is the other platform handled, or explicitly out of scope?
- Keyboard: edge-to-edge Android + `KeyboardAvoidingView` (catalog §8).
- Back button and gesture on Android: does it close sheets and modals first, and does it
  leave unsaved edits safely?
- Notifications (`expo-notifications`): does a tap handler work from the killed state?
  Channel changes need a native rebuild.
- Deep links: every route param validated, since a malformed `primaryTag` must not crash
  `decks/[primaryTag]`.
- Orientation: landscape is supported on some screens (`docs/landscape-catalogue.md`).

## Accessibility and text

- `accessibilityLabel`/`accessibilityRole` on icon-only buttons, and `selected`/`checked`
  state exposed.
- Touch targets ≥ 48 dp including `hitSlop`.
- Font scaling: no fixed-height text containers without the fixed-box rule (catalog §7),
  and the largest font scale tested for new chrome.
- Reduced motion respected for new animations. Blur needs a solid fallback.
- Gesture-only actions need an alternative (for Flow grading, `accessibilityActions` is a
  standing proposal, not a finding).

## i18n and content

- Hard-coded English in UI strings, where the surrounding screen is localised.
- RTL: `start`/`end`, not `left`/`right`.
- IPA and diacritics: rendered in every style's faces (Compact's IPA fallback; font
  coverage in `docs/design/font-coverage.md`).
- Cloze and HTML content rendered through the right strip function (`stripAnkiHtml` for
  Anki).

## Security (scaled to this app)

App data lives on the device. Convex is for auth, entitlement, sync and capture.

- No secrets in `EXPO_PUBLIC_*` or in the source. Server keys belong only in Convex
  deployment env.
- Every Convex function that reads user data refuses a null identity (catalog §9).
- WebViews: `allowFileAccessFromFileURLs` stays false. Card HTML from imported decks is
  untrusted, so check for new `originWhitelist`/`javaScriptEnabled` surface or
  `onMessage` handlers that act on content.
- Logs don't print tokens, DEKs or backup keys.
- The encrypted-backup DEK path: anything touching Clerk `privateMetadata` or the
  `dek.ts` action is 🔴-sensitive.
