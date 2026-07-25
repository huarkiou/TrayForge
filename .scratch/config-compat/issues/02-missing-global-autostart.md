# 02 — Missing top-level `autostart` global switch

Status: needs-triage

## Summary

Python 版 TrayForge 的 config.json 顶层有 `"autostart": false` 作为全局开关，可以一键关闭所有进程的自动启动，无需逐个修改进程配置。

Flutter 版只有两种 autostart：
- 每个进程独立的 `autostart` 字段
- OS 级别的开机自启注册（`Autostart` service）

缺少全局一键覆盖的能力。

## Impact

- 用户无法快速关闭所有 autostart
- 修改配置保存后顶层 `autostart` 字段会被静默丢弃

## Comments
