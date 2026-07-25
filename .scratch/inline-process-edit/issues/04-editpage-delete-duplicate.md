# 04 — ProcessEditPage Delete + Duplicate

**What to build:** The process edit form gains two new AppBar buttons, shown only in edit mode: a red "Delete" button and a "Duplicate" button. Delete shows a confirmation dialog (with extra warning if the process is running), then removes the process and pops back. Duplicate copies the process with a "(copy)" suffix and pops back.

**Blocked by:** 02 — Dashboard card edit flow

**Status:** ready-for-agent

- [ ] AppBar actions in edit mode: `[Delete]` `[Duplicate]` `[Save]` (left to right). In add mode: `[Save]` only
- [ ] Delete button: red `TextButton`. Tapping shows confirmation dialog — "Stop and delete?" if running, "Delete process?" if stopped, with a Cancel option
- [ ] On Delete confirmation: if running, calls `SettingsViewModel.stopProcess(name)` as fire-and-forget; then calls `SettingsViewModel.delete(editIndex)`; then pops the edit page
- [ ] Duplicate button: `TextButton` between Delete and Save. Tapping calls `SettingsViewModel.copy(editIndex)`, then pops the edit page
- [ ] Tests: Delete/Duplicate buttons absent in add mode; Delete shows confirmation dialog; Duplicate calls `copy` and pops; button order is Delete, Duplicate, Save
