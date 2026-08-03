# trayforge Domain Glossary

Single-context glossary for the trayforge codebase. Terms here name the
concepts the code is organised around; see `docs/adr/` for decisions.

## Process

A configured external program trayforge manages. Declared in the config as
a `ProcessConfig` (name, command, cwd, encoding, singleton, autostart,
maxRestarts, webuiPattern, cleanupCwd, deleteBeforeStart).

## ProcState

The lifecycle state of a Process: `stopped`, `starting`, `running`,
`stopping`, `crashed`, `cooldown`.

## ProcessController

The deep per-process module owning a Process's full lifecycle: the state
machine, launch sequence (shlex, env, cwd-relative exe resolution,
singleton guards, cleanupCwd, deleteBeforeStart), kill-tree stop, crash
restart + cooldown, pid file, output wiring, and its streams. One instance
per configured Process.

Interface decisions (ADR-worthy, recorded here as agreed):

- **Config is a parameter, never read from disk.** `start(config)` /
  `toggle(config)` receive the resolved `ProcessConfig` from the
  coordinator; the controller holds no `ConfigStore`.
- **`toggle` owns the start/stop decision** (active → stop, terminal →
  start). Viewmodels call it instead of re-deciding.
- **`applyRemoval` is immediate**: set the manual-stop flag (so the exit
  handler doesn't restart), kill the handle if alive, delete the pid file,
  dispose. Idempotent in any state. The launch sequence checks a `removed`
  flag before each side-effecting step so an in-flight `start` can't
  resurrect pid files or touch a disposed pipeline.
- **`stop` during `starting` is pending-stop**: a no-op there would let
  the launch sequence finish and end up `running` despite the user's
  stop. `stop()` sets a pending-stop flag; the launch sequence checks it
  right after obtaining the handle and kills immediately. Same mechanism
  as `removed`.
- **Dispose is safe against late continuations**: `_setState` and system
  messages guard on closed controllers/disposed pipeline, so an in-flight
  `stop()` continuation or exit handler can't throw after `applyRemoval`
  disposed the controller.
- Streams (`output`, `webUi`, `state`) are owned by the controller;
  `getState` reports `stopped` for unknown names.

## ProcessManager

The coordinator module: holds the name→ProcessController map
(materialized for every configured Process on init/reload, **diff-based**
— only removed names are disposed, only new names created; kept names
keep their live streams), applies config reload diffs (removals via
`controller.applyRemoval`), runs autostart, scans stale pid files at
init, and exposes the single facade viewmodels talk to. Its per-process
methods delegate to controllers; `cooldownDuration` and `flushNow` stay
on the facade as forwarding seams for existing tests. Materialization
happens **before** `onConfigReloaded` is emitted, so viewmodels always
subscribe to real streams.
