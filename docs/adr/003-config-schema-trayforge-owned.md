# ADR 003: Config schema is TrayForge-owned (Python parity dropped)

**Status:** Accepted
**Date:** 2026-08-04

## Context

The `config.json` schema was previously kept in lockstep with the Python
trayforge JSON schema, and the README plus `ConfigStore` doc comments still
describe it that way. The dashboard layout preference (`dashboard_layout`)
needs to persist somewhere, and the only persistent store is `config.json`.

## Decision

Python parity is dropped. The schema now evolves freely for TrayForge's own
needs, and UI preferences (starting with `dashboard_layout`, following the
existing `output_refresh_ms` / `output_history_limit` globals) live in the
config globals. Stale references to Python compatibility in README and
`ConfigStore` comments should be read as historical.
