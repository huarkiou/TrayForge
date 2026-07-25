# 01 - Config hot-reload & executable path resolution

Status: resolved

## Problem

1. 运行时手动复制 `config.json` 到数据目录后，程序无法感知变化，托盘菜单和 Dashboard 不会刷新。
2. `ProcessManager.start()` 中，`cmd` 的相对路径（如 `.\python_embeded\python.exe`）和仅存在于 cwd 中的裸文件名（如 `NapCatWinBootMain.exe`）无法被 `Process.start` 找到。Dart 的 `Process.start` 在 Windows 上不会在子进程的 `workingDirectory` 里搜索 executable。

## Fix

1. **ConfigStore.reload()**: `lib/services/config_store.dart` — 新增 `reload()` 方法，触发 `configChanged` 流。
2. **TrayViewModel.buildMenu()**: `lib/viewmodels/tray_viewmodel.dart` — 托盘右键菜单新增 "Reload Settings" 菜单项。
3. **ProcessManager.start()**: `lib/services/process_manager.dart` — executable 路径解析策略：
   - 含路径分隔符的相对路径（如 `.\python_embeded\python.exe`）→ 相对于 cwd 解析为绝对路径
   - 裸文件名且 cwd 中存在该文件 → 解析为绝对路径
   - 裸文件名且 cwd 中不存在 → 保持原样走 PATH

## Comments
