# 01 Screenshot + annotate

Done 2026-09-17 (steps 1 to 3). What changed while building it is in PLAN.md under Status.

Package `ToolScreenshot`, tool id `screenshot`, row "Screenshot", hotkey ⌘⇧2. Depends on 00.

## Decisions
- Quick capture by default: region / window / screen through the shared picker (mint style). Capture lands immediately in the pipeline: copy image + save + history (defaults). Pill shows a thumbnail with an **Annotate** button for 6 s; clicking it opens the editor on the saved file.
- Annotate later from any screenshot row in Recent/History (hover button).
- Editor tools v1: arrow, box, text, blur, number badge. Undo/redo. Colours: accent, white, ink. Two stroke sizes. Nothing else (no freehand, crop, ellipse, highlighter).
- PNG at native pixels (2x on Retina). Option row **Scale**: 2x (default) / 1x. 1x downsamples with Lanczos via CoreImage.
- Window mode keeps the macOS shadow on transparent PNG. Background padding/gradient deferred.
- Save folder default `~/Pictures/Deskpouch`, file `Screenshot yyyy-MM-dd HH.mm.ss.png`. Annotated export writes `… annotated.png` beside it; never overwrites the original.

## Structure
```
ToolScreenshot/
  ScreenshotTool.swift        phases: idle, picking, capturing; keyPressed toggles picker
  ScreenshotSettings.swift    scale, folder, windowShadow, key (defaults `shot.*`)
  Annotate/
    AnnotationModel.swift     value type: [Annotation] enum (arrow, box, text, blur, badge), selection, undo stack. Pure, tested.
    AnnotationCanvas.swift    SwiftUI Canvas over the image, hit testing, drag handles
    AnnotationRenderer.swift  draws the model onto a CGContext for export (same code the canvas uses)
    AnnotateDocument.swift    EditorDocument: toolbar (tool chips), copy, export
```

## Flow
1. ⌘⇧2 → `ShareableContentLoader` → picker. Return/click captures.
2. `StillCapture` returns CGImage → `ToolResult(toolID:, image:, fileURL: staging png)` → pipeline saves, copies, logs with thumb.
3. Pill `.captured(thumb, annotate: () -> Void)` new `PillState` case. 6 s auto-hide, hover pauses.
4. Annotate opens `EditorWindowController.present(AnnotateDocument)`; Export emits a second `ToolResult` (kind screenshot, file `… annotated.png`), pipeline again.

## Blur
Pixelate the region rather than gaussian: area-averaged 16 pt blocks (larger than UI text is tall) with per-block noise seeded from the mark's id. Changed after review on 2026-09-17: the planned 6 pt CIPixellate blocks kept text shapes that de-pixelation tools can match.

## Tests (Core/Capture only, no SCK)
- AnnotationModel: add, move, undo/redo, hit test order (last drawn on top).
- Renderer: golden PNG for a fixed model at 1x (compare pixel hash).
- Filename and unique-suffix rules.

## Verify on machine
`DESKPOUCH_DEMO=annotate` captures a preset rect, opens the editor from the newest row with sample annotations and exports; check clipboard has PNG and the file pair exists in `~/Pictures/Deskpouch`.

## Panel
Row status: "2x · Pictures/Deskpouch". Tool view: card (tile, description, ⌘⇧2 keycaps), chips Copy / Save / Reveal / History, option rows Scale, Folder, Window shadow, Shortcut.
