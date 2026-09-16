# 00 Foundation: shared capture, editor window, tool switches

Decided 2026-09-16. Lands before any v2 tool. Everything below is a prerequisite for at least two tools.

## 1. Package `DeskpouchCapture`

New local package at `Packages/DeskpouchCapture`, depends on `DeskpouchCore` only. Capture tools depend on Core + Capture. Rule update in PLAN.md: "tools import Core and Capture only; Capture never imports a tool; Core never imports Capture."

Moves out of `ToolScreenRecorder` (git mv, no behaviour change):
- `CaptureGeometry.swift`
- `Picker/PickerModel.swift`, `Picker/PickerView.swift`, `Picker/PickerWindowController.swift`
- `windowZOrder()`, `shareableContent()`, `ownApplication(fallback:)` and `makeModel(from:)` from `ScreenRecorderTool` become `ShareableContentLoader` in Capture.

New in Capture:
- `PickerStyle`: tint (amber for record, mint for still, text mode for OCR) and toolbar label, so the same picker reads differently per tool.
- `StillCapture`: `func capture(_ selection: PickerSelection, scale: CaptureScale, windowShadow: Bool) async throws -> CGImage` over `SCScreenshotManager.captureImage(contentFilter:configuration:)`. Region and screen use `SCContentFilter(display:excludingWindows:)`; window uses `desktopIndependentWindow` with `ignoreShadowsSingleWindow = false` and `shouldBeOpaque = false` for the transparent shadow PNG.
- `ImageWriter`: PNG/JPEG via ImageIO, `downscale(to: 1x)`.
- `OverlayWindow`: borderless, non-activating, screen-saver level, ignores mouse, one per screen. Used by loupe (03), click ripple and keystroke chip (06).
- `ToolResult` gains `image: CGImage?` in Core (see 3).

Recorder keeps `ScreenRecorder`, `RecorderSettings`, `ScreenRecorderTool`; its exclusion changes from app-wide to per-window in plan 06, not here.

Tests: existing `PickerModel` and `CaptureGeometry` tests move with the files. `swift test` in Capture must stay Xcode-free (no SCK calls in tests).

## 2. `EditorWindowController` in Core

One window chrome for Annotate (01), Diff (04) and Trim (05). AppKit `NSWindow` (titled, full-size content view, custom toolbar hidden), SwiftUI content. Layout per DESIGN.md: panel gradient ground, 18 padding, header row (title 15/600, close), content area, bottom bar with tool-supplied chips left and `Copy` / `Export` buttons right (amber primary). Escape closes, ⌘W closes, ⌘C copies, ⌘S exports. Remembers frame per tool id. Never more than one editor open; opening a second replaces the content.

API:
```swift
public protocol EditorDocument: AnyObject { var title: String { get }; func makeView() -> AnyView; func copy(); func export() async throws -> ToolResult? }
public final class EditorWindowController { public func present(_ doc: EditorDocument, for toolID: String) }
```
`export()` returns a `ToolResult` the shell feeds to the pipeline like any capture, so chips on the tool card decide what happens.

## 3. Pipeline: image results and new actions

- `ToolResult.image: CGImage?` (in memory, for copy and thumbnails) alongside `fileURL`. `copy` with an image and no text puts PNG + TIFF on the pasteboard (`OutputEffects.copyImage`).
- `HistoryStore`: add column `kind TEXT` (text, recording, screenshot, meeting, convert) and `thumb_path TEXT` (small JPEG under Application Support/Deskpouch/thumbs). Migration: `ALTER TABLE` guarded by `PRAGMA table_info`. `History` filter grows Screenshots and Meetings segments.
- New `OutputAction.appendToFile` (plan 08) with `ToolOutputConfig.appendTarget: AppendTarget?` (path template + heading). Ordered after `saveToFolder`.
- Panel chips list per tool comes from `Tool.offeredActions` (new protocol member, default all except `notify` and `appendToFile`).

## 4. Tool switches in General

- `GeneralSettings.enabledTools: Set<String>` under `tools.enabled` (default: every registered tool id, so a tool added in a new build shows up on first launch).
- `Tool` gains `func activate()` / `func deactivate()` with no-op defaults. Shell calls `deactivate` on switch-off: unregister hotkeys, release models and capture sessions. `attach` still happens once at launch.
- General view: "Tools" section between Sounds and History, one 40 pt row per tool: tile, name, switch. Off hides the row from the Tools list and its history rows stay.
- `ShellState` stops hardcoding `voice`/`screen` rows: `ToolsSection` iterates `shell.tools.filter(enabled)` and asks each tool for its row (`Tool.rowStatus`, `Tool.tile`). This refactor is the biggest item here and is what stops the panel code doubling with each tool.

## 5. Hotkey inventory

| combo | tool | notes |
|---|---|---|
| Right Option (hold) | Voice | existing |
| Right Command (hold) | Voice note | plan 08 |
| ⌘⇧4 | Screenshot | macOS default must be turned off in System Settings › Keyboard › Shortcuts › Screenshots; if `RegisterEventHotKey` fails the row shows "taken" like the recorder already does |
| ⌘⇧6 | Record screen | existing |
| ⌘⇧8 | Text grab | plan 02 |
| ⌘⇧9 | Color | plan 03 |
| ⌘⇧M | Meeting | plan 07 |

`KeyCombo` gets named statics for each. Every combo remains editable through the existing `ShortcutRecorder`.

## Order of work

1. Capture package + move (half a day).
2. Tool switches + row refactor (one day).
3. Editor window shell (one day).
4. Pipeline image support + history columns (half a day).

Verify: existing recorder demo modes still pass, `DESKPOUCH_DEMO=options` shows the Tools section, switching Record off frees ⌘⇧6 (check with another app binding it).
