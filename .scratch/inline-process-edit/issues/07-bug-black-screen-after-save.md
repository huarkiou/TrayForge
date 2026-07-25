# 07 — 保存/删除/复制后页面黑屏

**Status:** resolved

**Blocked by:** 05

**What happened:** 点击 ProcessEditPage 的 Save / Delete / Duplicate 后，`Navigator.pop()` 回到了一个空路由栈 — 所有路由（包括 Dashboard）都被 `pushAndRemoveUntil((_) => false)` 清除了。

**Root cause:** `_navigateToEdit` 使用 `pushAndRemoveUntil(context, editPage, (_) => false)` — 谓词 `(_) => false` 对所有路由返回 false，因此移除**全部**路由（包括 Dashboard）。ProcessEditPage pop 后，Navigator 为空 → 黑屏。操作本身成功（ConfigStore 已写入），重启后数据正确。

**Fix:** 将谓词改为 `(route) => route.isFirst`，仅保留 Dashboard（第一条路由），移除中间页面（如 DetailPage）。同时移除了 DetailPage 的 `onEditTap` 中多余的 `Navigator.pop()` 调用 — `pushAndRemoveUntil` 会自动清除 DetailPage。

**Commits:**
- `45734c3` — 初始实现
- `e135b45` — 修复

## Comments

用户报告：复制/删除/保存点击后页面黑屏，手动退出重启后发现之前操作的功能正常。

确认修复后用户反馈：功能正常。
