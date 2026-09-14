# Deskpouch: plan

Personal macOS menubar app hosting small capture tools. First two tools: voice dictation and screen recording. More tools added as needs arise. Possible public release far in the future.

## Decisions

### Shape
- One menubar app. No "studio" window, no launcher.
- Tools are compile-time modules conforming to a `Tool` protocol, registered in one list in the app target.
- No runtime plugin system. Can be added later if third parties ever write tools.

### Stack
- Native Swift 6, SwiftUI for settings and panels, AppKit for menubar, floating overlays, and anything SwiftUI handles poorly.
- Minimum macOS 15 (Sequoia). Apple Silicon only.
- Reasons: ScreenCaptureKit `SCRecordingOutput` (macOS 15+), CoreML on the Neural Engine for transcription, global hotkeys, paste into frontmost app.

### Tool contract (`Tool` protocol)
- Identity: id, name, icon, required permissions.
- Triggers: hotkeys it wants, menubar entry. Shell registers and resolves conflicts.
- Lifecycle: `activate()`, `deactivate()`, capture state exposed for menubar icon.
- UI slots: optional settings view, optional overlay view.
- Output: emits a `ToolResult` (text, file, or both, plus metadata) to the shell.

### Shell owns
- Global hotkeys.
- Permissions (screen recording, microphone, accessibility), prompted on first use per tool.
- Overlay system: one non-activating floating panel any tool can push a small view into.
- Output pipeline: per-tool configurable after-capture actions: copy, paste into frontmost app, save to folder, reveal in Finder, run shell command, notification.
- Lightweight history: SQLite log of every `ToolResult`. Last few shown in menubar for re-copy or reveal. No library UI.
- Settings window.

### Voice tool, v1
- Hold-to-talk hotkey (default: Right Option). Release to transcribe and paste.
- Transcription: local, Parakeet TDT 0.6B v3 via FluidAudio (CoreML, Neural Engine). Model downloaded on first use.
- `Transcriber` protocol so WhisperKit or a cloud provider can be added later.
- Overlay pill shows level meter while recording, spinner while transcribing, brief "pasted" flash.
- Default actions: paste + copy.
- Out of scope for v1: toggle mode, LLM cleanup, modes, custom vocabulary.

### Screen recorder tool, v1
- Hotkey opens a region / window / full screen picker (native Cmd+Shift+5 feel). Click to start.
- ScreenCaptureKit. System audio plus optional mic. H.264 mp4 (plays everywhere, Slack-friendly).
- Menubar icon becomes a red timer while recording. Same hotkey or menubar click stops. No floating controls over the recording.
- Default actions: save to folder + copy file + notification.
- Out of scope for v1: trim, editor, cursor effects, zoom, webcam overlay, gif export, annotations.

### Repo structure
Single repo. Local Swift packages so the compiler enforces boundaries.

```
deskpouch/
  Deskpouch.xcodeproj
  App/                    thin app target: menubar, settings window, tool registry
  Packages/
    DeskpouchCore/        Tool protocol, ToolResult, pipeline, history, hotkeys, overlay, permissions
    ToolVoice/            depends on Core only
    ToolScreenRecorder/   depends on Core only
```

Rules: tools never import each other. Core never imports a tool. Tests live per package, mostly on Core (pipeline, history, hotkey conflicts). Capture code is not unit tested.

### Distribution
- Unsigned local builds for now.
- Developer ID + notarization + Sparkle when a build is first shared with a teammate or sold.
- Never App Store (sandbox blocks paste, system audio, hotkeys).

### Visible surfaces, v1
Design direction settled 2026-09-14: "Mint ground, amber accent", custom chrome. Full spec with tokens and components in `design/DESIGN.md`. Mocks in `design/mocks/Final*.dc.html`.

- One floating panel drops from the menubar icon and is the whole app. No Settings window, no dashboard, no library.
- Panel: header, tool cards (active card highlighted, each expands in place for its options), Recent list (last 3, tile per item), footer with General and Quit.
- General is a second view inside the same panel behind a back chevron: launch at login, sounds, menubar timer, history toggles, clear history, permissions status, version and updates.
- Pill: bottom-center, non-activating. Listening (bar meter), transcribing (grows into a card, text types in), pasted (undo hint), recording (timer, dims, Stop).
- Menubar icon: idle glyph, listening mini meter, recording red timer.
- Region picker: dimmed screen, amber selection with corner brackets and dimension chip, bottom pill toolbar.
- No onboarding beyond permission prompts. Custom controls (keycaps, chips, toggles, popups) are drawn by us, not AppKit defaults.

## Build order
1. Menubar app with one hotkey that shows the overlay pill.
2. Voice end to end: hold, record, Parakeet, paste.
3. History and after-capture actions.
4. Screen recorder end to end.
5. General view and per-tool options inside the panel.

The `Tool` protocol starts as a stub for voice and gets reshaped by the second tool. Do not design it upfront.

## Open items
- Default hotkeys for screen recorder.
- Output folder name and location (likely `~/Movies/Deskpouch` for video, transcripts in history only).
- Video quality preset and max length guard.
- "Don't keep transcripts" toggle before any public release.
