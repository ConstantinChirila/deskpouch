# 04 Screenshot diff

Lives inside `ToolScreenshot` (no new row, no hotkey). Depends on 00 (editor, history kinds) and 01.

## Decisions
- Input: History view, filter Screenshots, two rows selected (⌘-click or checkbox on hover) → **Compare** button in the header. Only screenshot rows are selectable.
- Each screenshot row gets **Recapture** (hover): re-runs `StillCapture` with the rect and display stored for that capture, then opens Compare with the pair. Needs `HistoryStore` column `capture_rect TEXT` (JSON: display id + rect), written by 01.
- Diff opens in the editor: modes Slider (drag divider), Onion (opacity slider), Pixels (mismatched pixels tinted record colour over a dimmed base). Header shows "N px differ · P %". Sizes differ → letterbox to the larger, note "sizes differ".
- Export writes `Diff yyyy-MM-dd HH.mm.ss.png` of the current mode to the screenshot folder and logs it (kind screenshot).
- Comparison is per-pixel with tolerance 0 by default; option chip **Fuzz** (0 / 2 / 8 per channel) for antialiasing noise.

## Structure
```
ToolScreenshot/Diff/
  ImageDiff.swift        pure: (CGImage, CGImage, fuzz) → (mask CGImage, count, percent) via vImage or a plain loop on RGBA8 buffers. Tested with synthetic images.
  DiffDocument.swift     EditorDocument with the three modes
  DiffView.swift
```

## Tests
Identical images → 0; one-pixel change → 1; fuzz hides a ±1 change; size mismatch reported.

## Verify
Two demo captures of the panel with one chip toggled → Compare shows exactly the chip region.
