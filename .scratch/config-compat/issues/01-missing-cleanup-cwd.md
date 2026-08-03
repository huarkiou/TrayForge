# 01 — Missing `cleanup_cwd` field

Status: done (implemented in `da9659c` — `cleanup_cwd` field + `_cleanupCwd` in ProcessManager)

## Summary

Python 版 trayforge 的每个 process 配置支持 `cleanup_cwd: true/false`，启动前自动清理 cwd 下的残留文件（锁文件等）。Flutter 版完全没有这个字段及其功能。

## Impact

- NapCat、AstrBot 等依赖 `cleanup_cwd` 清理残留锁文件的进程，迁移到 Flutter 版后需要手动清理。
- 修改配置保存后该字段会被静默丢弃。

## Existing mitigations

- Flutter 版有 `delete_before_start`（手动指定文件列表，更精确）
- Flutter 版有 PID 文件孤儿进程检测和清理

但两者都不等价于自动扫描清理 cwd。

## Comments
