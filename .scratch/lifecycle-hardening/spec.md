# Lifecycle hardening follow-ups

Follow-up hardening for the ProcessController lifecycle, found in the full
review of issues #1–#7 (2026-08-04).

## Scope

- `01-exit-orphan.md` — the only open ticket: exiting the app while a
  launch is in flight can leave an orphaned OS process (pre-existing gap,
  same class as the #6 config-removal orphan).

## Resolved in the review pass (commit 914cb8c)

- `stop()` during `cooldown` cancels the scheduled auto-restart (lands on
  `stopped`); restart-cancel extracted into `_cancelRestart()`.
- `reloadConfig` autostart skips kept processes that are running /
  `starting` / `stopping` (no double-launch, no fighting an in-flight
  stop).
- `_configuredNames` refreshed before the removal loop — removed names
  stay inert mid-reload (no phantom controller).
- Stale-exit guard: a replaced launch's exit handler neither restarts nor
  cleans up the new launch; the in-flight stop continuation is guarded the
  same way (and still lands `stopped` when the exit handler cleaned up
  first).
