# 02 — ConfigStore: 配置读写/备份/裁剪/校验

**What to build:** Configuration persistence layer. Users can read and write their process configurations, with automatic backup and validation. Compatible with Python trayforge JSON schema.

**Blocked by:** 01 — Foundation (needs `ProcessConfig` and `AppConfig` models)

**Status:** done

**Commit:** `25b0c63` — feat: ConfigStore — config persistence with backup, prune, and validation

- [x] `ConfigStore.load()` — reads `config.json` from data dir, returns `AppConfig?` (null if file missing); on JSON parse error, backs up corrupted file to `backups/config.<timestamp>.corrupted.json` and returns null
- [x] `ConfigStore.save(config)` — serializes to JSON (snake_case to match Python trayforge, indented), backs up old file before overwrite
- [x] Backup: copies old `config.json` to `backups/config.<timestamp>.json` before each save
- [x] Prune: deletes oldest backup files when `backups/` directory exceeds 10MB
- [x] `ConfigStore.validate(processConfig)` — rejects name with `/` or `\`, validates `webui_pattern` as compilable regex
- [x] `ConfigStore.configChanged` — a change-notification stream so subscribers can reload
- [x] JSON keys match Python trayforge: `cwd`, `cmd`, `encoding`, `singleton`, `autostart`, `webui_pattern`, `delete_before_start`, `max_restarts`, `env`, `output_history_limit`, `output_refresh_ms`
