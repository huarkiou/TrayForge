# 01 — Prefactors: safe dispose + incremental \_rebuild

**What to build:** Two internal refactors with no user-visible change. (1) `ProcessViewModel` survives disposal gracefully by making `addListener`/`removeListener` no-ops after `dispose()` — any page still holding a reference won't crash. (2) `DashboardViewModel._rebuild` matches existing ViewModels by name and reuses them instead of recreating all from scratch, preserving accumulated output across config reloads.

**Blocked by:** None — can start immediately.

**Status:** done (`45734c3` — inline process edit feature)

- [ ] `ProcessViewModel` gains a `_disposed` flag; `addListener` and `removeListener` return immediately when disposed; `dispose()` sets the flag then cleans up subscriptions and controllers as before
- [ ] `DashboardViewModel._rebuild` builds a name→VM map from existing instances, reuses matches, creates new VMs for new names, and disposes only those no longer present
- [ ] Existing `DashboardViewModel` tests still pass; new test verifies reused VM retains output lines after `_rebuild`
- [ ] Existing `ProcessViewModel` tests still pass; new test verifies `addListener` is a no-op after dispose and does not throw
