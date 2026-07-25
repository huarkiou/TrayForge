# ADR: Navigation + Safe Dispose (A+J)

**Status:** implemented

## Context

ProcessEditPage 的 Save/Delete/Duplicate 会通过 `ConfigStore.save()` 同步触发
`configChanged` → `DashboardViewModel._rebuild()` → dispose 旧 ProcessViewModel。
如果用户从 DetailPage → EditPage 的路径进入，pop 后回到 DetailPage 时持有的
VM 引用已失效。

## Decision

### J：ProcessViewModel 安全 dispose（防御层）

- `addListener` / `removeListener` 在 `_disposed == true` 后变为 no-op
- `dispose()` 设置标志后正常清理资源
- 效果：任何页面持有已 dispose 的 VM 也不会因 `ListenableBuilder` 崩溃

### A：强制回主页（策略层）

- `DashboardScreen._navigateToEdit` 使用 `pushAndRemoveUntil` 确保编辑完成后
  回到 Dashboard
- 谓词 `(route) => route.isFirst` — 保留 Dashboard，清除中间页面（如 DetailPage）
- 初始实现误用 `(_) => false`（清除了 Dashboard 导致黑屏），已修正

### 增量 _rebuild

- `DashboardViewModel._rebuild` 按 name 匹配复用现有 VM，避免拖拽排序清空输出

## Consequences

- Save 后总是回到 Dashboard → 不会停留在已改名的进程的 DetailPage
- 安全 dispose 保证即使有中间帧引用已 dispose 的 VM 也不会崩溃
- 代价：从 DetailPage 编辑后无法自动回到 DetailPage（未来 B2 方案可解）

## See also

- Bug #07: pushAndRemoveUntil((_) => false) 导致黑屏
- Future: B2 方案（稳定 ID 匹配）可消除强制回主页的 UX 代价
