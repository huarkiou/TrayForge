# Inline Process Edit — Spec

Status: `ready-for-agent`

## Problem Statement

Process configuration management is trapped inside the Settings page: to add, edit, copy, delete, or reorder processes, the user must navigate Dashboard → Settings → find the process row. This is a three-step detour that disconnects process management from the Dashboard where users actually monitor their processes. The Settings page has become a grab-bag of process CRUD mixed with global settings, with no process-level actions reachable from the card or detail page.

## Solution

Move all per-process actions (add, edit, duplicate, delete, reorder) onto the Dashboard and into the process edit form itself. The Settings page becomes purely global: output refresh interval, history limit, and autostart toggle. Process cards gain edit access; the Dashboard gains inline add and drag-to-reorder; the edit form gains delete and duplicate.

## User Stories

### 从卡片直接编辑
1. As a user viewing the Dashboard, I want to tap an edit icon on a process card, so that I can adjust that process's configuration without navigating through Settings
2. As a user viewing a process detail page, I want to tap an edit icon in the AppBar, so that I can fix configuration issues I noticed while reading the output log
3. As a user, I want the edit icon to be visually distinct from the global Settings gear, so that I don't confuse "edit this process" with "open global settings"
4. As a user, I want the edit button on the card to be placed after the start/stop toggle, so that it doesn't interfere with the primary card interactions
5. As a user, I want tapping the card body to still open the detail page, so that the existing interaction stays consistent

### 编辑表单增强
6. As a user, I want the edit form to be pre-filled with the process's current configuration, so that I can make targeted changes without re-entering everything
7. As a user, I want to save my edits and be returned safely to the Dashboard, so that I never see a stale or crashed page after a process is modified
8. As a user editing a process, I want a "Delete" button next to Save, so that I can remove the process I'm currently looking at without navigating back to a list
9. As a user editing a process, I want a "Duplicate" button next to Save, so that I can create a new process based on the current one as a starting point
10. As a user about to delete a running process, I want a confirmation dialog warning me, so that I don't accidentally stop and remove an active service
11. As a user duplicating a process, I want to be returned to the Dashboard immediately, so that I can see the new copy appear and edit it if needed
12. As a user who performs any destructive or identity-changing action (delete, rename, duplicate), I want to be returned to the Dashboard automatically, so that I never encounter a stale or crashed intermediate page

### 添加进程
13. As a user on the Dashboard, I want a prominent "+" button in the AppBar, so that I can add a new process in one tap
14. As a user seeing the empty welcome screen, I want the "Add Process" button to open the add form directly, so that I don't have to go through Settings

### 排序
15. As a user on the Dashboard, I want to drag and drop process cards to reorder them, so that my preferred order is reflected immediately without losing accumulated output

### Settings 精简
16. As a user opening Settings, I want to see only global configuration options, so that I can adjust system-wide behavior without wading through a process list

## Implementation Decisions

### Dashboard — 添加按钮
- A `+` `IconButton` is added to the Dashboard AppBar actions, to the **left** of the existing Settings gear icon. Tooltip: "Add process".
- Tapping it navigates to `ProcessEditPage` in add mode (no `initial` config, no `editIndex`).
- Uses `Icons.add` icon.
- Visible on both the dashboard (card list) and welcome (empty) screen states.

### Dashboard — 空状态欢迎页
- The welcome screen's "Add Process" button currently navigates to `SettingsPage`. It is changed to navigate directly to `ProcessEditPage` (add mode), matching the new `+` AppBar button behavior.

### Dashboard — 拖拽排序
- The `ListView.builder` in `_buildDashboardBody` is replaced with `ReorderableListView.builder`.
- Each item receives `key: ValueKey(vm.name)` for stable identity during reorder.
- `onReorder` delegates to `SettingsViewModel.reorderItem` (already exists on the ViewModel).

### ProcessCard — 编辑按钮
- `ProcessCard` gains an optional `onEditTap` (`VoidCallback?`) parameter.
- When non-null, an `Icons.edit` `IconButton` is rendered in the `_Header` row, after the `ToggleButton`, as the rightmost element.
- The icon is compact (`visualDensity: VisualDensity.compact`) with tooltip "Edit process".
- When the callback is null, the icon is omitted.

### ProcessCard — 拖拽手柄
- `ProcessCard` gains an optional `dragHandleIndex` (`int?`) parameter.
- When non-null, a `ReorderableDragStartListener` wrapping an `Icons.drag_handle` icon is placed at the start of the `_Header` row, before the `StatusDot`.
- When null, no drag handle is rendered. The card remains unaware of whether it is inside a reorderable list.

### ProcessDetailPage — 编辑按钮
- `ProcessDetailPage` gains an optional `onEditTap` (`VoidCallback?`) parameter.
- When non-null, an `Icons.edit` `IconButton` is added to the AppBar actions, positioned **before** the existing clear-output, search, and toggle buttons.
- Tooltip: "Edit process".

### 导航与 index lookup
- `DashboardScreen` provides both `onEditTap` callbacks.
- The callback searches `SettingsViewModel.processes` by matching `ProcessConfig.name` against the `ProcessViewModel.name` to find the `editIndex`.
- If not found (config was deleted while the view was open), the button does nothing — no crash, no error dialog.

### 方案 A+J：安全 dispose + 强制回主页

**问题**：`ConfigStore.save()` 同步触发 `configChanged` → `DashboardViewModel._rebuild()` 同步 dispose 旧 `ProcessViewModel`。EditPage pop 后，任何中间页面（如 `ProcessDetailPage`）持有的 VM 引用已失效，`ListenableBuilder` 崩溃。

**两层防护**：

#### J：ProcessViewModel 安全 dispose（防御层）
- `ProcessViewModel` 新增 `_disposed` 标志。
- `addListener` / `removeListener` 在 disposed 后变为 no-op。
- `dispose()` 设置标志后正常清理 `StreamSubscription`、`StreamController`。
- **效果**：即使任何页面持有已 dispose 的 VM，`ListenableBuilder` 也不会崩溃——只是显示静态残余数据，直到页面被移除。
- **无内存泄漏**：重资源在 `dispose()` 中正常释放；残余引用仅在短暂窗口期内存在，页面被 pop/GC 后消失。

#### A：强制回主页（策略层）
- `ProcessEditPage` 的 Save、Delete、Duplicate 操作完成后，调用方（`DashboardScreen.onEditTap`）使用 `Navigator.pushAndRemoveUntil` 或等效方式确保最终停在 Dashboard。
- Delete 弹出确认对话框确认后执行；Duplicate 直接执行；Save 直接执行。
- **效果**：用户从任何页面进入编辑，保存/删除/复制后总是回到 Dashboard。不会停留在 DetailPage 看一个已删除/已改名的进程。

**交互**：J 确保中间帧不崩溃；A 确保最终态正确。两者独立互补。无任何场景会导致崩溃。

### ProcessEditPage — 按钮顺序
- AppBar actions, left to right: `[Delete]` `[Duplicate]` `[Save]`.
- Delete (red, destructive, leftmost), Duplicate (secondary), Save (primary, rightmost).

### ProcessEditPage — Delete 按钮
- A red "Delete" `TextButton` in the AppBar actions, leftmost.
- Only shown in edit mode (`isEditing == true`). Not shown in add mode.
- Tapping it shows a confirmation dialog:
  - If the process is running: "Stop and delete?" with content explaining the process will be stopped.
  - If stopped: "Delete process?" with a warning that this cannot be undone.
- On confirmation: if running, calls `SettingsViewModel.stopProcess(name)` as fire-and-forget (does not wait for process exit). Then calls `SettingsViewModel.delete(editIndex)`, then pops the edit page with result `true` (`Navigator.pop(context, true)`).
- The `true` result signals the caller that the process was deleted and any intermediate pages (e.g. detail page) should also be popped.

### ProcessEditPage — Save 按钮
- On save, calls `SettingsViewModel.edit()` or `.add()` as appropriate, then pops the edit page.
- The caller (`DashboardScreen`) always navigates back to the Dashboard after edit completion, using `Navigator.pushAndRemoveUntil` to clear any intermediate pages (e.g. `ProcessDetailPage`) from the stack. This ensures the user never returns to a page holding a potentially-disposed `ProcessViewModel`.

### ProcessEditPage — Duplicate 按钮
- A "Duplicate" `TextButton` in the AppBar actions, between Delete and Save.
- Only shown in edit mode (`isEditing == true`). Not shown in add mode.
- Tapping it calls `SettingsViewModel.copy(editIndex)`, then pops the edit page. The caller forces navigation back to Dashboard, same as Save.
- The duplicated process (with "(copy)" suffix) appears on the Dashboard immediately via `configChanged`.

### Settings 页精简
- The entire process list (`ReorderableListView` of `_ProcessRow` widgets) is removed.
- The FAB ("Add Process") is removed.
- Retained: global output refresh interval field, history limit field, autostart toggle.

### DashboardViewModel — 增量 _rebuild
- `_rebuild` is changed from full dispose-and-recreate to incremental: matching existing `ProcessViewModel` instances by name are reused (preserving accumulated output), new processes get new ViewModels, and removed processes are disposed.
- This ensures drag-to-reorder does not clear output.

### 回调命名统一
- Both `ProcessCard` and `ProcessDetailPage` use the name `onEditTap` for their optional edit callback.

### 布局总结

Dashboard AppBar actions: `[+] [gear]`

ProcessCard header (no WebUI, no drag): `StatusDot | Name | ToggleButton | [edit]`
ProcessCard header (with WebUI, no drag): `StatusDot | Name | [copyURL] | ToggleButton | [edit]`
ProcessCard header (with drag, no WebUI): `[drag] StatusDot | Name | ToggleButton | [edit]`
ProcessCard header (with drag, with WebUI): `[drag] StatusDot | Name | [copyURL] | ToggleButton | [edit]`

ProcessDetailPage AppBar actions: `[edit] [clear] [search] [toggle]`

ProcessEditPage AppBar actions (add mode): `[Save]`
ProcessEditPage AppBar actions (edit mode): `[Delete] [Duplicate] [Save]`

## Testing Decisions

- **What makes a good test**: Verify external behavior — button presence, button tap triggers callback or navigation. Do not test internal widget tree details of `ProcessEditPage` from card/dashboard tests.
- **Modules tested**:
  - `ProcessCard` — edit icon appears when `onEditTap` is non-null and is absent when null; tapping it calls the callback. Drag handle appears when `dragHandleIndex` is non-null.
  - `ProcessDetailPage` — edit icon appears when `onEditTap` is provided; tapping it calls the callback.
  - `DashboardScreen` — tapping the edit icon on a card navigates to `ProcessEditPage`; tapping `+` AppBar button navigates to `ProcessEditPage` in add mode; drag-to-reorder triggers `SettingsViewModel.reorderItem`.
  - `ProcessEditPage` — Delete button shows confirmation dialog and pops with `true`; Duplicate button calls `SettingsViewModel.copy` and pops; Delete/Duplicate are absent in add mode; button order is Delete, Duplicate, Save (left to right).
  - `SettingsPage` — process list is absent; FAB is absent; global fields remain functional.
  - `DashboardViewModel` — incremental `_rebuild` reuses existing ViewModels by name; removed processes are disposed.
- **Prior art**: Existing tests in `test/widgets/process_card_test.dart`, `test/screens/dashboard_screen_test.dart`, `test/screens/process_detail_screen_test.dart`, `test/viewmodels/dashboard_viewmodel_test.dart`. Follow the same fake-based patterns.

## Out of Scope

- Redesigning the `ProcessEditPage` form fields themselves
- Adding edit/delete/duplicate to the tray menu or any other surface
- Batch/bulk operations on multiple processes
- Undo for delete

## Further Notes

- Name-based index lookup is O(n) but n is small (number of configured processes). No performance concern.
- With A+J, there is no scenario where a disposed `ProcessViewModel` causes a crash. J (safe dispose) is the safety net; A (force-return-to-Dashboard) is the UX strategy. Together they eliminate the disposed-VM problem entirely.
- `ReorderableDragStartListener` does not crash when there is no `Reorderable` ancestor — the drag gesture simply has no effect. So `ProcessCard` with a non-null `dragHandleIndex` remains safe in non-reorderable contexts (e.g. widget tests that don't wrap in `ReorderableListView`).
- The `+` Add button is always visible in the AppBar, even on the welcome screen, so users never have to hunt for the add action.
- `ConfigStore.save()` fires `configChanged` synchronously (via `StreamController.add()` on a broadcast stream). This means `DashboardViewModel._rebuild()` and `SettingsViewModel._reload()` run inside the `save()` call, before `save()` returns.

### 未来方向：稳定 ID 方案 (B2)

当前 A+J 通过强制回主页解决安全性问题，但存在 UX 代价：即使用户只改了 WebUI 端口（不改名），保存后也被踢回 Dashboard。

**B2 终极方案**：
1. `ProcessConfig` 新增不可变 `id` 字段（UUID），创建时生成，序列化到 JSON
2. `DashboardViewModel._rebuild` 按 `id` 匹配而非 `name` 匹配
3. `ProcessManager` 内部索引从 `Map<String, _ProcessRuntime>` 改为 `Map<String, _ProcessRuntime>`（key 改为 `id`），所有公开 API（`start`、`stop`、`stateStream`、`outputStream`）签名从 `String name` 改为 `String id`
4. 改名时 VM 和运行状态按 `id` 保留，输出不中断，进程不重启
5. 旧版配置文件（无 `id` 字段）加载时自动生成并原地写入

**收益**：
- Save 不改名 → 正常返回 DetailPage，VM/输出/进程状态全保留
- Save 改名 → 正常返回 DetailPage，VM/输出/进程状态全保留，仅标题更新
- Delete → 返回 Dashboard（与 A+J 行为一致）

**不在本 spec 范围内**。B2 涉及 schema 迁移、ProcessManager 重构、所有 ViewModel/Stream API 签名变更，应作为独立架构项目推进。A+J 是 B2 的安全前身，不会被 B2 的未来实现阻碍。
