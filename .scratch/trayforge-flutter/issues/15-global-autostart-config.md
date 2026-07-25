# 15 — Global autostart: persist to config.json?

**Type:** discussion  
**Status:** wontfix

---

## Background

Python trayforge saves the global "Launch at startup" toggle **both** to the OS registry AND to `config.json` as `"autostart": true/false`.

Flutter trayforge (current) only writes the OS registry via `Autostart.enable()` / `disable()`. The toggle state is not persisted in config.

## Question

Is persisting to config.json actually useful, or is the registry-only approach fine?

### Pro (persist to config)
- Config is self-contained — export/share config.json and the autostart preference travels with it
- Python compatibility — same schema

### Con (registry only)
- Redundant — registry is the source of truth
- Config.json should describe managed processes, not app lifecycle
- One less place for state to get out of sync

## Notes

- The `settings_page.dart` toggle already reads registry state on load and toggles correctly
- The difference is only observable if a user manually edits config.json or migrates it between machines

## Comments
