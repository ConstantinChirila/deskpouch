# 09 Image convert

Package `ToolImageConvert`, tool id `convert`, row "Convert". No hotkey. Depends on 00.

## Decisions
- Input: drop image files (or an image from the pasteboard) onto the tool row or its card; Finder › Services › "Convert with Deskpouch" via `NSServices` in Info.plist (`NSSendFileTypes: public.image`, handled in `AppDelegate` through `NSApp.servicesProvider`).
- Presets as chips and option rows: Format WebP / PNG / JPEG (AVIF only if `CGImageDestination` accepts `public.avif` on macOS 15, to be checked in the first hour of work; otherwise dropped), Quality 80 (WebP/JPEG), Scale 1x from 2x (halves pixels, base name unchanged), Max width (off / 1200 / 1600 / 2000), Strip metadata (on).
- Output written beside the source: `name.webp`; if the name exists, `name 2.webp` (existing `uniqueURL` rule). One history row per output (kind convert, tile shows before → after size). Chips: Reveal / Copy file / History. Batch of N files shows one pill "Converted 12 files · 4.1 MB → 0.9 MB".
- WebP encoding via ImageIO with `UTType.webP` is unverified for macOS 15; ImageIO has decoded WebP since macOS 11 and encoded it since 14 by several reports. If encoding fails, fall back to bundling libwebp as a Swift package (first choice `SDWebImageWebPCoder` is too heavy; use a plain libwebp binary target) and note it in README.

## Structure
```
ToolImageConvert/
  ImageConvertTool.swift   accepts URLs, runs jobs on a background task, emits results
  ConvertJob.swift         pure settings → (CGImage → Data) using ImageIO, tested with a generated 200x100 image
  DropTarget.swift         SwiftUI onDrop for the row and card
```

## Tests
PNG→JPEG size shrinks, 2x→1x halves dimensions, max width clamps and keeps aspect, metadata stripped (no EXIF dictionary in output), unique naming.

## Verify
Drop three PNG exports from Figma: WebP files appear beside them, history shows sizes, Finder service entry appears after the first launch (may need `/System/Library/CoreServices/pbs -update`).
