# 01 — Foundation: Models + OutputPipeline + Logger

**What to build:** Define the core data types, output processing utilities, and application-level logging. No UI, no process management — just pure-library code that everything else depends on.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `ProcessConfig` model with all fields: `name`, `cwd`, `cmd`, `encoding`, `singleton`, `autostart`, `webui_pattern`, `delete_before_start`, `max_restarts`, `env`
- [ ] `AppConfig` model with `output_history_limit`, `output_refresh_ms`, `processes` list, and a `Default` constructor that provides the two example processes (NapCat + AstrBot)
- [ ] `ProcState` enum: `stopped`, `starting`, `running`, `stopping`, `crashed`, `cooldown`
- [ ] `shlex.split(posix: false)` utility for parsing `cmd` string into argument list
- [ ] `OutputPipeline.stripAnsi(line)` — regex-based ANSI escape code removal
- [ ] `OutputPipeline.tryDetectWebUi(line, pattern)` — regex match, returns capture group 1 as URL or null
- [ ] `Logger` — file logger with rotation: 1MB max per file, keep 3 backups, UTF-8, writes to `{data_dir}/logs/trayforge.log`
- [ ] `Logger.getDataDir()` — resolves `TRAYFORGE_DATA_DIR` env var, falls back to `%LOCALAPPDATA%/TrayForge` (Win) or `$XDG_DATA_HOME/TrayForge` (Linux)
