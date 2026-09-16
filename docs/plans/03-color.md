# 03 Color picker

Package `ToolColor`, tool id `color`, row "Color", hotkey ⌘⇧9. Depends on 00 (`OverlayWindow`, `StillCapture`).

## Decisions
- ⌘⇧9 shows a loupe that follows the cursor: 11x11 pixel grid magnified to 132 pt, centre pixel outlined, value line under it (hex plus nearest Tailwind name), all on an `OverlayWindow` per screen. Cursor hidden while active.
- Click copies one string in the chosen format. Esc cancels. Arrow keys nudge one pixel.
- Format option: hex (default) `#f59e0b`, rgb `rgb(245 158 11)`, hsl, oklch `oklch(0.79 0.17 70)`, SwiftUI `Color(red:green:blue:)`. Stored under `color.format`.
- Nearest Tailwind v4 default palette name shown in the loupe as a hint only (ΔE2000 in Lab; show when ΔE < 6, else "custom"). Palette is a static table in the package, 22 hues × 11 steps.
- WCAG contrast pairing deferred (documented as v2: shift-click second colour).
- History row per pick: swatch tile, value, format; Copy re-copies.

## Sampling
Per mouse move: `StillCapture` of a 11x11 pt region around the cursor at native scale is too slow via SCScreenshotManager (~30 ms). Instead capture the whole display once on activation with `SCScreenshotManager`, keep the CGImage, sample from it; recapture when the cursor changes display. Colours read in the display's colour space, converted to sRGB for output; option row "Colour space: sRGB / Display P3" later if needed.

## Structure
```
ToolColor/
  ColorTool.swift          activate loupe, sample, click → emit ToolResult(text: formatted)
  ColorFormats.swift       pure conversions, tested against known values
  TailwindPalette.swift    static table + nearest()
  LoupeView.swift
```

## Tests
Conversions (hex/rgb/hsl/oklch for six reference colours), nearest palette entry for exact and near matches, formatting strings.

## Panel
Row status: "hex · Tailwind hints". Tool view: chips Copy / History, option rows Format, Tailwind hints (toggle), Shortcut.
