# 01 — dashboard_layout persistence

**What to build:** The Dashboard layout preference can be persisted. The
application config carries a two-valued layout (`list` | `grid`), serialized
as `dashboard_layout` in config.json, defaulting to `list` when absent or
invalid. The settings layer exposes a getter and a setter for the layout; the
setter persists through the globals-only save path (no process reload). Both
save paths (globals-only and the full save used by reorder/add/edit/duplicate)
round-trip **all** globals, so changing the refresh interval, the history
limit, or reordering processes never silently resets the stored layout.
Stale "Python compatible" mentions in the README and the config store docs
are removed (per ADR 003 — the schema is TrayForge-owned).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `dashboard_layout` round-trips both values in the config JSON; missing
      or invalid values load as `list` (foundation tests)
- [ ] Setting the layout persists to config.json; loading the saved config
      yields the stored layout value
- [ ] Stale "Python compatible" mentions removed
