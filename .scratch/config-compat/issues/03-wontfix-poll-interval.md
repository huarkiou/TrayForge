# 03 — Dropped `poll_interval_ms` (by design)

Status: wontfix

## Summary

Python 版有顶层 `poll_interval_ms` 配置项。Flutter 版已改为事件驱动架构
（`handle.exitCode.then(...)` 异步监听），不再需要轮询，该字段已主动移除。

## Comments
