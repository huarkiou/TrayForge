# 07 — Dashboard Cards: 进程卡片 + 启停 + 输出预览

**What to build:** The main dashboard fills with real process data. Each process gets a card showing status, last N output lines, and action buttons. Cards are navigable — tap one to push the detail page (even if detail page is not yet implemented, the navigation target can be a stub).

**Blocked by:** 06 — Tray + Window Shell, 05 — ProcessManager Resilience

**Status:** done (commit `e274889`, polish `edfe032`)

- [x] `DashboardViewModel` (ChangeNotifier): holds list of `ProcessViewModel` instances, one per configured process
- [x] `ProcessViewModel` (ChangeNotifier): mirrors `ProcState` from ProcessManager, exposes bounded output buffer (last N lines, limited by `output_history_limit`), exposes WebUI URL when detected, exposes toggle start/stop command
- [x] Dashboard widget: if no processes configured, show welcome screen: "No processes configured" + "Add Process" button → opens Settings; if processes exist, show scrollable `ListView` of `ProcessCard` widgets
- [x] Each ProcessCard: Material `Card` with name + status dot (green/grey/red circle) + start/stop toggle `IconButton`
- [x] Card body: monospace text widget showing last ~15 lines of output, ellipsis at `maxLines`
- [x] WebUI button: appears only when URL is detected, copies URL to clipboard via `Clipboard.setData`; shows brief snackbar "URL copied"
- [x] Tap card → `Navigator.push` to detail page (stub `ProcessDetailPage` with just name in AppBar, "Coming soon" body)
- [x] New output from ProcessManager stream pushes to ProcessViewModel's output buffer; trim old lines when exceeding `output_history_limit`
- [x] Card toggle button: immediate visual feedback — stop button shows `stopping` state (spinner), start button shows `starting` state; reverts to actual state on ProcessManager callback (success or failure)
- [x] When ConfigStore.configChanged fires and processes list becomes empty after reload, switch to welcome screen
- [x] When corrupted config is detected on startup, alert dialog before showing welcome screen

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: Optimistic state cleared only on terminal states, not transitional

Spec says toggle shows a spinner and "reverts to actual state on ProcessManager
callback (success or failure)." `ProcessManager.start()` emits `starting`
synchronously inside the method body — before the process has actually succeeded
or failed. If `_optimisticState` is cleared on every state callback (including
`starting`/`stopping`), the spinner disappears in the same frame it was set,
never rendering on screen.

The fix: `_onState()` clears `_optimisticState` only for terminal states
(`running`, `stopped`, `crashed`, `cooldown`). Transitional states (`starting`,
`stopping`) leave the optimistic state intact. The `state` getter (`_optimisticState
?? _state`) continues to return the correct value because both are the same
state. The `isTransitioning` getter (`_optimisticState != null`) correctly
returns `true` until a terminal state arrives.

### D2: Double-toggle guarded by both optimistic and real state

`toggle()` has two layers of guard:
1. `if (isTransitioning) return;` — blocks when optimistic state is non-null.
2. `if (_state != ProcState.starting && _state != ProcState.stopping)` —
   blocks start when already starting/stopping.

Layer 2 is needed because ProcessManager emits `starting` synchronously inside
`start()`, clearing `_optimisticState` (before D1 fix) and making layer 1
ineffective. After D1, layer 2 is still valuable: it handles the edge case
where a transitional state was set by something other than `toggle()` (e.g.
autostart).

### D3: Config corruption detection lives in `main.dart`, not `ConfigStore`

`ConfigStore.load()` deliberately returns `null` for both "file missing" and
"corrupted file" — the caller can't distinguish them after the fact. The
corruption check (`File.existsSync()` + `load() == null`) therefore lives in
`main.dart` before ProcessManager and DashboardViewModel are constructed.
Moving it into ConfigStore would require changing the load() return type or
adding a separate probe method — both heavier than the 3-line inline check.

### D4: `configCorrupted` as `bool`, not an enum

Only one failure mode matters today (file exists but isn't parseable). If
more failure modes appear later (permission denied, schema version mismatch),
refactor to an enum. The flag is consumed only via `initState` → post-frame
callback, so `clearCorruptedFlag()` doesn't call `notifyListeners()` — no
listener depends on it.

### D5: Scaffold lifted above `ListenableBuilder`

During code review the duplicated `Scaffold`+`AppBar` was lifted from two
branch methods into a single `build()` method. Side benefit: the `AppBar` no
longer rebuilds on every ViewModel change — only the `body` (wrapped in
`ListenableBuilder`) does.

### D6: `_Header` resolves `ScaffoldMessenger` from its own context

The first cut passed `ScaffoldMessengerState` from `ProcessCard.build` into
`_Header`'s constructor. Removed in polish: `_Header.build` calls
`ScaffoldMessenger.of(context)` directly. Both widgets share the same
`Scaffold` ancestor, so the result is identical. One less parameter.

### D7: "Add Process" button defers to Settings when available

The button shows a `'Settings not yet implemented'` snackbar with a TODO
comment. Navigating to a real Settings page requires ticket 09.

### D8: Duplicated test helpers follow existing codebase pattern

`_writeConfig`, `_testConfig`, `_MockProcessHandle` appear in multiple test
files. Extracting a shared `test/helpers/test_utils.dart` was considered but
deferred: the codebase already has 4 copies of `_writeConfig` across test
files, and each test file is self-contained. A shared helper would couple
tests that are currently independent.
