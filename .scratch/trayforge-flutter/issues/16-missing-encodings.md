# 16 — Missing encoding options: add gb2312 / cp936 / shift_jis / latin-1?

**Type:** discussion  
**Status:** done

---

## Background

Python TrayForge encoding dropdown offers:

```
utf-8, gbk, gb2312, cp936, shift_jis, latin-1
```

Flutter TrayForge (current) only offered:

```
utf-8, gbk
```

## Decision

Added `cp936` and `latin-1`. Not adding `gb2312` (strict subset of GBK — no practical difference) or `shift_jis` (no known demand from target audience).

Final dropdown: **utf-8 / gbk / cp936 / latin-1**

