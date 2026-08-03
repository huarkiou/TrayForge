# Deepen the process lifecycle into ProcessController

**Status:** ready-for-agent

## Problem Statement

From the user's perspective, process management has three sharp edges:

- Deleting a process from Settings while it is mid-`starting` leaves it
  running invisibly — an orphaned OS process plus a stale pid file that
  the next launch may mistake for a live process.
- Clicking stop (tray or dashboard) while a process is `starting` does
  nothing; the launch sequence finishes anyway and the process ends up
  `running` against the user's intent.
- The start/stop decision ("what does toggle mean in this state?") is
  re-implemented in two places and drifts.

From the developer's perspective, `ProcessManager` is an ~800-line module
where the genuinely deep per-Process behavior (state machine, launch
sequence, crash restart, cooldown, pid file, output wiring) sits behind a
wide, implicit contract: callers must know the optimistic-state protocol,
the init ordering, and the fact that stream accessors materialize phantom
entries.

## Solution

Extract a deep per-Process module — the **ProcessController** — that owns
one Process's full lifecycle behind a small interface, with config passed
in as a parameter. `ProcessManager` becomes a coordinator with an
**unchanged public facade**: it holds the name→controller map, applies
config reload diffs, runs autostart, scans stale pid files at init, and
forwards per-Process calls to controllers. The start/stop decision is
centralized in `toggle`; config removal always terminates the process
(no more orphans); stop during `starting` is honoured (pending-stop).

The user-visible result: no orphaned processes, no stale pid files, no
"stop did nothing" surprises — and everything else behaves exactly as
before.

## User Stories

1. As a trayforge user, I want to delete a process from Settings while it
   is starting, so that it actually stops instead of running invisibly.
2. As a trayforge user, I want to delete a running process from Settings,
   so that its OS process is killed and its pid file removed.
3. As a trayforge user, I want to click stop while a process is starting,
   so that the process does not launch afterwards.
4. As a trayforge user, I want the tray toggle to work during `starting`,
   so that a half-launched process can be aborted.
5. As a trayforge user, I want no stale pid files left behind after config
   edits, so that a later launch never kills an unrelated process that
   reused the PID.
6. As a trayforge user, I want start/stop/toggle/restart behaviour to be
   unchanged for all normal flows, so that the refactor is invisible to me.
7. As a trayforge developer, I want the start/stop decision in one place,
   so that tray and dashboard toggles cannot drift apart.
8. As a trayforge developer, I want the controller to receive config as a
   parameter, so that it never reads the store and the double-read `!`
   NPE path disappears.
9. As a trayforge developer, I want to drive the lifecycle without a
   ConfigStore on disk, so that controller-level tests are cheap to write.
10. As a trayforge developer, I want stream access for unknown names to be
    inert, so that typos or stale UI never materialize phantom state.
11. As a trayforge developer, I want controllers materialized per
    configured Process before `onConfigReloaded` fires, so that viewmodels
    always subscribe to real streams.
12. As a trayforge developer, I want the existing 1414-line
    `process_manager_test.dart` to stay green through the migration, so
    that the facade delegation is regression-protected for free.
13. As a trayforge developer, I want diff-based materialization, so that
    kept processes keep their live streams across reloads.
14. As a trayforge developer, I want removal to be safe against in-flight
    start/stop continuations, so that no async callback throws after the
    controller is disposed.

## Implementation Decisions

- **New deep module `ProcessController`**, one instance per configured
  Process. Owns: the state machine, the launch sequence (shlex split,
  env merge, cwd-relative exe resolution, singleton guards, cleanupCwd,
  deleteBeforeStart, lenient decode), kill-tree stop, crash restart +
  cooldown, pid file, output wiring, and its own streams (`output`,
  `webUi`, `state`).
- **Config is a parameter, never read from disk.** `start(appConfig,
  procConfig)` and `toggle(appConfig, procConfig)` receive the resolved
  configs from the coordinator: the `AppConfig` (global pipeline limits
  `outputHistoryLimit` / `outputRefreshMs`) and the per-process
  `ProcessConfig` (command, env, encoding, webuiPattern, flags). The
  controller holds no `ConfigStore`; today's double config read collapses
  into one `load()` + one lookup, and the `!` NPE path disappears.
  Pipeline limits stay start-time (as today — reload does not hot-apply
  them to running pipelines).
- **Constructor dependencies:** the process runner (injected), data dir
  (pid files), optional logger, cooldown duration (the existing test
  seam, forwarded through the facade).
- **`toggle` owns the decision.** Mapping, as agreed:
  `isActive` (running | starting) → stop; `isTerminal` (stopped |
  crashed | cooldown) → start. Viewmodels call `manager.toggle(name)`
  instead of re-deciding.
- **`applyRemoval` is immediate and idempotent in any state:** set the
  manual-stop flag (exit handler won't restart), kill the handle if
  alive, delete the pid file, dispose. The launch sequence checks a
  `removed` flag before each side-effecting step (pid write, pipeline
  configure, exit-listener attach) so an in-flight start cannot
  resurrect pid files or touch a disposed pipeline.
- **`stop` during `starting` is pending-stop:** set a flag; the launch
  sequence checks it right after obtaining the handle and kills
  immediately. Same mechanism as `removed`.
- **Dispose is safe against late continuations:** the controller's
  `_setState` and system-message pushes guard on closed controllers /
  disposed pipeline, so an in-flight stop continuation or exit handler
  cannot throw after removal.
- **`ProcessManager` becomes the coordinator with an unchanged facade.**
  Public surface stays: `init`, `start`, `stop`, `getState`,
  `stateStream`, `outputStream`, `webUiStream`, `clearOutput`,
  `reloadConfig`, `onConfigReloaded`, `dispose` — plus `cooldownDuration`
  and `flushNow` kept as forwarding seams for existing tests, and one
  **new facade method `toggle(name)`**. Per-Process methods delegate to
  the controller for `name`.
- **Diff-based materialization:** on init and each reload, controllers
  exist for every configured Process; only removed names are disposed
  (via `applyRemoval`), only new names created; kept names keep their
  live streams. Materialization completes **before** `onConfigReloaded`
  is emitted. Unknown names get inert streams and `stopped` from
  `getState`.
- **`reloadConfig` removal path:** all removed Processes go through
  `applyRemoval` regardless of state (today only `running` ones are
  stopped) — this is the orphan fix.
- **Encoding resolution** stays inside the launch sequence; the lenient
  decoder behaviour is unchanged.
- **Landing order (incremental; broken into tickets 01–06 in the issue
  tracker):**
  1. Extract `ProcessController` + facade delegation — purely behavioural,
     lazy creation preserved, existing tests stay green.
  2. pending-stop + closed-guards (stop during `starting` honoured; safe
     dispose).
  3. `manager.toggle(name)`; switch the two viewmodel call sites.
  4. Diff-based materialization (controllers per configured Process;
     inert streams + `stopped` for unknown names).
  5. `reloadConfig` → `applyRemoval` for all states; orphan-fix tests.
  6. Prune redundant manager-level tests once coverage lands.

## Testing Decisions

- **One seam: the `ProcessManager` facade.** All behaviour — state
  transitions, restart/cooldown, toggle, pending-stop, removal, guards —
  is observable through the unchanged public interface, so no new test
  seam is introduced. If a behaviour can only be tested past the facade,
  that is a signal the module shape is wrong.
- **A good test drives the public interface and asserts on observed
  effects:** mock-observed kills (`killedPids`, `handle.kill`), `starts`
  count, pid file existence under the temp dir, state-stream emissions.
  Never asserts on internal fields or private methods.
- **Modules tested:** `ProcessManager` through the facade
  (`process_manager_test.dart`); the controller's behaviour is exercised
  through it. Mock capabilities are extended, not the seam.
- **Prior art:** existing patterns in `process_manager_test.dart` —
  `MockProcessRunner`/`MockProcessHandle` with exitCode completions,
  `writeConfig` + temp-dir ConfigStore, `flushNow` for output inspection,
  `cooldownDuration` for restart timing.
- **Mock extensions (recommended for robustness, not strictly required; not
  new seams):** the synchronous-turn interleave already covers the basic
  cases — `start` suspends at its first await while the handle is still
  null, so `stop`/`reloadConfig` called in the same turn deterministically
  hit the pending-stop / removed path. Gateable `start` and `killPid`
  (Completer-held futures) make the `starting`-window and in-flight-stop
  tests robust against future reordering of the launch sequence.
  - Note: `killPid` does not complete the mock handle's exit — tests that
    need the exit handler to fire after removal call
    `handle.completeExit(code)` explicitly, then assert no restart
    (`starts.length` unchanged) thanks to the manual-stop flag.
- **New test cases:**
  - pending-stop: stop during `starting` kills the launched process; state
    never reaches `running`.
  - removal during `starting`: pid file not rewritten by the in-flight
    start; late exit does not trigger a restart.
  - removal during in-flight stop: no throw from the stop continuation.
  - `applyRemoval` for non-running states (starting, cooldown): killed,
    pid file gone, controller disposed.
  - toggle mapping: `running`/`starting` → stop; terminal → start.
  - unknown names: inert streams, `getState` → `stopped`, no state created.
  - kept names across reload: streams stay live (no re-subscribe needed).
  - existing restart/cooldown/pid tests continue to pass unchanged.

## Out of Scope

- The other architecture-review candidates: output-path collapse,
  encoding-seam honesty (incl. real GBK support), process-CWD seam.
- UI changes beyond the two toggle call sites (dashboard button + tray).
- Dashboard laziness or window behaviour (ADR 001 territory).
- Tray click behaviour (ADR 002 territory).
- Any change to encoding options or the lenient-decoder behaviour.

## Further Notes

- No ADR conflicts: ADR 001 (tray-only startup) and ADR 002 (tray click
  behaviour) are untouched by this work.
- `CONTEXT.md` already carries the settled glossary entries for
  `ProcessController` and `ProcessManager`, including the agreed
  interface decisions (config-as-param, toggle ownership, applyRemoval
  semantics, pending-stop, closed-guards, diff materialization).
- **Overlap with ticket `.scratch/config-notification/issues/01`**
  (triaged `done`): its remaining ask (repair the stale `_procs` leak in
  `reloadConfig`) is absorbed by this spec's diff-based materialization
  and `applyRemoval`; the notification-move half was already done
  (`onConfigReloaded` lives on the facade, `ConfigStore` has no
  notifier). No further triage needed.
- No other open tickets overlap: `inline-process-edit/01-06` and
  `config-notification/02` are triaged `done` (implemented in
  `45734c3`/`44e72eb`); `config-compat/02` (global autostart switch) is
  `wontfix` (aligns with `trayforge-flutter/15`).
- The orphan fix (story 1–2) is the highest-value user-visible outcome
  of this refactor; the rest is locality and test-surface payoff.
