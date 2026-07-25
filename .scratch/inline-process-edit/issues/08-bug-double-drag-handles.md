# 08 — 卡片右侧出现多余的拖拽手柄

**Status:** resolved

**Blocked by:** 03

**What happened:** 每张进程卡片左右两侧各出现一个 ≡ 拖拽手柄，右侧的是多余的。

**Root cause:** `ReorderableListView.builder` 的 `buildDefaultDragHandles` 参数默认为 `true`，会在每行 trailing edge（右侧）自动渲染一个拖拽手柄。加上我们在 `ProcessCard._Header` 左侧手动添加的 `ReorderableDragStartListener`，每张卡就有两个手柄。

**Fix:** 设置 `buildDefaultDragHandles: false`，只保留左侧自定义手柄。

**Commit:** `2cbd8f9`

## Comments

用户通过截图发现每张卡片左右各有一个拖拽横线图标，要求只保留左侧的。
