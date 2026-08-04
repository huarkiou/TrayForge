# Exit while a process is `starting` leaves an orphaned OS process

**Type:** task
**Status:** needs-triage
**Labels:** needs-triage

## Summary

Found in the full review of issues #1–#7 (2026-08-04). The config-removal
orphan was fixed by `applyRemoval` (#6), but the same class of gap remains
on the app-exit path.

`_exitApp` (lib/main.dart) calls `_processManager.stop(name)` for processes
in `running`/`starting` state. For a `starting` process, `stop()` only sets
the pending-stop flag — the kill happens when the launch sequence obtains
the handle. `_exitApp` then disposes the manager, destroys the tray/window,
and calls `exit(0)` without waiting for the in-flight launch to land. If
`Process.start` was invoked but the Dart await hadn't resumed, the launched
child survives the parent's exit as an invisible orphan (no pid file was
written, so the next launch cannot detect it).

Pre-existing: the old code's `stop()` was a no-op during `starting`, so the
orphan gap predates the ProcessController refactor. #6 fixed the delete
path; the exit path was not in its scope.

## Repro (real world)

1. Autostart a slow-to-launch process (or a process whose command hangs in
   shell startup).
2. Within the launch window (<1s typically), quit the app from the tray.
3. The child process keeps running with no pid file and no manager.

## Acceptance criteria

- [ ] Exiting the app while a launch is in flight never leaves an orphaned
      child process behind.
- [ ] No regression to the normal exit path (running processes still
      stopped via `stop()`).

## Fix sketch

Track in-flight launches and await them before `exit(0)`:

- `ProcessManager` records the start future per name (e.g. a
  `Map<String, Future<void>>` populated in `start()`/`toggle()`, cleared on
  completion) — or `ProcessController` exposes an in-flight-launch future.
- `_exitApp`: after `stop()` for `starting` names, await the in-flight
  launches; the pending-stop machinery kills the process as soon as the
  handle arrives.
- Test: mock `startGate` held open, `_exitApp`-equivalent flow awaits the
  launch, kill observed, no throw.

## Notes

- `dispose()` during an in-flight launch has the same gap: the launch
  sequence checks `_disposed` after each await and bails, but an OS child
  already spawned survives. Awaiting in-flight launches before
  `ProcessManager.dispose()` covers both.
- Not related to the pending-stop / stale-exit guards from the #7 review
  follow-ups (those were implemented in the same review pass).
