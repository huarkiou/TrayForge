# 08 — Process Detail Page: 全量输出 + 搜索 + 自动滚动

**What to build:** Tapping a process card opens a full detail page with the complete output log. New lines auto-scroll to the bottom unless the user manually scrolls up. A search bar lets users filter output text.

**Blocked by:** 07 — Dashboard Cards

**Status:** done

- [x] `ProcessDetailPage` with `AppBar` showing process name + status dot + Start/Stop button + Copy WebUI button (when URL available, copies to clipboard)
- [x] Full output displayed in a scrollable, read-only, monospace text body
- [x] Auto-scroll: when new output arrives and user is within ~100px of the bottom, auto-scroll to the latest line
- [x] Scroll lock: if user manually scrolls up beyond the auto-scroll threshold, pause auto-scrolling; resume when user scrolls back near bottom
- [x] Search bar: `IconButton` in AppBar toggles a search `TextField`; typing filters the displayed output lines to only those containing the search text (case-insensitive)
- [x] Search bar dismissal clears the filter and shows all lines again
- [x] Output is preserved when switching between cards and returning to the same detail page (ProcessViewModel holds the buffer, not the widget)

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: `ProcessDetailPage` takes `ProcessViewModel`, not `String processName`

The stub accepted `processName` but the full implementation needs state,
output lines, WebUI URL, and toggle — all owned by `ProcessViewModel`.
Passing the ViewModel also satisfies the output-preservation requirement:
a shared ViewModel survives `Navigator.push`/`pop` cycles because
`DashboardViewModel._rebuild()` creates one `ProcessViewModel` per process
that lives as long as the dashboard.

### D2: AppBar state-dependent widgets wrapped in `ListenableBuilder`

The status dot, WebUI button, and toggle button sit in the AppBar — outside
the body's `ListenableBuilder`. Without their own `ListenableBuilder` wrappers,
they would not rebuild when the ViewModel notifies (e.g. spinner never appears
after `toggle()`). The title and actions each get a minimal-scope
`ListenableBuilder`.

### D3: `_initialScrollDone` bypasses the ~100px auto-scroll threshold once

When the page first opens, `ScrollController.position.pixels` is 0 and
`maxScrollExtent` is large — the ~100px threshold would immediately set
`_autoScroll = false`, and new output would never auto-scroll. A one-shot
`_initialScrollDone` flag jumps to bottom on the first ViewModel notification,
then hands control to the standard threshold logic. This is not scope creep:
the spec's threshold describes the steady state after the user has seen the
page, not the initial navigation into it.

### D4: Search uses `TextEditingController.addListener`, not `TextField.onChanged`

`onChanged` fires only on user keystrokes. `addListener` also fires when
`_searchController.clear()` is called programmatically (i.e. when dismissing
the search bar via `_toggleSearch`). This ensures clearing the search field
always restores the unfiltered output.

### D5: Search `TextField` has `suffixIcon` wired to `_searchController.clear()`

The clear icon is an `IconButton` (not a decorative `Icon`) so tapping it
clears the search text and restores all lines. The first pass had a
decorative-only `suffixIcon: Icon(Icons.clear)` with no action — caught in
code review and fixed.

### D6: `_StatusDot` and `ToggleButton` extracted to shared widgets

The original implementation duplicated these private classes from
`lib/widgets/process_card.dart`. Code review flagged Duplicated Code.
Extracted to `lib/widgets/status_dot.dart` and `lib/widgets/toggle_button.dart`.
`ToggleButton` takes an optional `visualDensity` parameter: the card passes
`VisualDensity.compact`, the AppBar omits it (default spacing). The visual
difference is intentional — a card button needs tighter spacing than an
AppBar action.

### D7: `_scrollToBottom()` helper deduplicates two identical `jumpTo` blocks

`_onViewModelChanged` had two near-identical `postFrameCallback` blocks that
both called `_scrollController.jumpTo(maxScrollExtent)`. Extracted into a
single `_scrollToBottom()` method. The initial-scroll path calls it
unconditionally; the auto-scroll path guards with `if (_autoScroll)`.

### D8: SnackBar for "URL copied" uses compact floating style

The first pass used a full-width `SnackBar` with 2-second duration. Code
review noted the feedback was larger than necessary for a clipboard
confirmation. Changed to `SnackBarBehavior.floating` with `width: 160` and
`duration: 1s` — a small floating pill that disappears quickly.

### D9: Empty states are Material Design baseline, not scope creep

"No output yet" (when output buffer is empty) and "No matching lines" (when
search finds nothing) were flagged as scope creep during review. They are
kept: a blank page is indistinguishable from a crashed page. These are
standard Material Design empty-state patterns.

### D10: `SelectableText` in body, not `Text`

The spec says "read-only". `SelectableText` provides read-only display +
copy-to-clipboard for free. Users can select and copy output lines without
leaving the page.

### D11: `_onViewModelChanged` fires on all VM changes, not just output

State transitions (stopped → running) also trigger the listener. The
`_autoScroll` guard makes this harmless: non-output changes don't cause
unwanted scrolling. No need for a separate output-only listener — the
overhead is one bool check.
