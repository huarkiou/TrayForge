# 12 — Code Review Fixes: Autostart, Ctrl+F, ProcState Extension, copyWith, WebUI Icon

**What to build:** Five small fixes surfaced by the final code review (全仓库审查 at `94c8674...HEAD`).

**Blocked by:** None — orthogonal to any in-progress work.

**Status:** done

---

## Task List

### 1. Autostart toggle (US 34)

> Spec: "As a user, I want optional autostart with the operating system"

`Autostart` service (`lib/services/autostart.dart`) is built and tested but never instantiated or wired to UI.

- [ ] Instantiate `Autostart(logger: _logger)` in `main.dart`
- [ ] Pass it to `SettingsViewModel` constructor
- [ ] Add `bool get autostartEnabled` (calls `_autostart.isEnabled()`) and `Future<void> toggleAutostart()` to `SettingsViewModel`
- [ ] Add a `SwitchListTile` labelled "Launch at startup" at the top of the Settings page, above the process list, separated by a divider

### 2. Ctrl+F keyboard shortcut (US 15)

> Spec: "As a user, I want to search/filter the output log (Ctrl+F)"

- [ ] Wrap `ProcessDetailPage` Scaffold body with `CallbackShortcuts` binding `SingleActivator(LogicalKeyboardKey.keyF, control: true)` → `_toggleSearch`

### 3. ProcState extension (smell: Repeated Switches)

Five call sites re-derive `ProcState` semantics independently.

- [ ] Add `extension ProcStateX on ProcState` to `lib/foundation/models.dart` with:
  - `bool get isActive` — `this == ProcState.running || this == ProcState.starting`
  - `bool get isTerminal` — `this != ProcState.starting && this != ProcState.stopping`
  - `Color get statusColor` — green for `running`, red for `crashed`, grey otherwise
- [ ] Update `lib/widgets/status_dot.dart`: replace `_color` switch with `state.statusColor`
- [ ] Update `lib/widgets/toggle_button.dart`: replace `viewModel.state == ProcState.running` with `viewModel.state.isActive`
- [ ] Update `lib/viewmodels/process_viewmodel.dart`: replace `state != ProcState.starting && state != ProcState.stopping` with `state.isTerminal`
- [ ] Update `lib/viewmodels/tray_viewmodel.dart`: replace `state == ProcState.running` with `state.isActive` (two sites: `_toggleProcess`, `buildMenu`)
- [ ] Update `lib/viewmodels/settings_viewmodel.dart`: replace `state == ProcState.running || state == ProcState.starting` with `state.isActive`

### 4. Remove unused copyWith clear flags (smell: Speculative Generality)

- [ ] Remove `clearCwd`, `clearEncoding`, `clearWebuiPattern`, `clearMaxRestarts`, `clearEnv` from `ProcessConfig.copyWith` in `lib/foundation/models.dart`
- [ ] Remove the test case "clears optional fields with clear flags" from `test/foundation/models_test.dart`

### 5. WebUI button icon (spec inconsistency)

- [ ] In `lib/widgets/process_card.dart`, change `Icons.open_in_browser` → `Icons.content_copy` (the detail page already uses `Icons.content_copy`)

---

## Notes

- Items 3 and 5 are one-line changes per site. Item 4 removes dead code. Items 1 and 2 are net-new but small.
- No behaviour change from items 3–5. Items 1–2 add missing spec features.
- The `_rebuild` / `_rebuildSubscriptions` duplication (smell finding 4) was discussed and left as-is — each is ~25 lines with clear purpose.

---

## Review Decisions

Code review (`94c8674...HEAD`) flagged three baseline smells. All predate this commit (全仓库审查范围). Decisions:

### D1 — Divergent Change in `process_manager.dart`

767 lines covering start/stop, restart/cooldown, PID CRUD, orphan cleanup, `delete_before_start`, output pipeline. These are all sub-responsibilities of "process lifecycle management" — cohesive, not divergent. The 11-runtime-bundle refactor already bundled per-process Maps into `_ProcessRuntime`. **Leave as-is.** Split when a new unrelated concern is added (e.g. graceful shutdown timeout, health checks).

### D2 — `_mergeByteStreams` (Speculative Generality)

14-line private method, single call site. Not speculative — a named helper for the stdout/stderr merge pipe improves readability of `start()`. Inlining two `listen` calls + a `StreamController` is noisier. **Rejected: false positive.** This is encapsulation, not speculative abstraction.

### D3 — Duplicated `Navigator.push` → `SettingsPage`

AppBar settings button and welcome "Add Process" button share ~6 lines of identical route code. Extraction to `_navigateToSettings()` saves 4 lines at the cost of one indirection. At this scale it's preference, not a defect. **Leave as-is.**
