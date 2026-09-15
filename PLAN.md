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
- Panel: header, tool cards (active card highlighted, each expands in place for its options), Recent list (last 5, tile per item), footer with General and Quit.
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

## Status (2026-09-15)

Milestones 1, 2 and 3 are implemented on the dev machine. Milestones 1 and 2 are committed; milestone 3 is uncommitted and verified with the Core tests plus the panel snapshot demo, not yet with a real dictation. `README.md` has build, permissions, and verification instructions.

Decisions made while implementing:
- Hotkeys use `NSEvent` global + local monitors, not a CGEvent tap. A tap could be created without Accessibility but was then silently starved by macOS.
- Builds sign with a local self-signed "Deskpouch Dev" certificate (`scripts/make-dev-cert.sh`, identity in `Signing.xcconfig`) so TCC grants survive rebuilds.
- Pill after release: "Transcribing" loader, immediate paste, short "Pasted into X". No transcript preview (design/DESIGN.md updated). A "Copied" state covers the no-target case; it never pastes into Deskpouch's own panel.
- Voice language is a persisted hint (`voice.language`, ISO 639-1, default system language) passed to Parakeet's decoder so names do not drift scripts. UI for it comes in milestone 5.
- `Tool` protocol v1: id, name, holdKey, `attach(ToolContext)`, `holdBegan`, `holdEnded`. Shell owns copy and paste via `OutputPipeline`.
- Superwhisper on the same machine also reacts to Right Option; quit it while testing.
- History is plain SQLite through the system `SQLite3` module (`HistoryStore`, one table, WAL). SwiftData rejected: it would pull a model container into Core for one table.
- `OutputPipeline` runs a fixed action order (copy, paste, save, reveal, shell, notify, history) through an injectable `OutputEffects`; tests use a recording fake. Paste with Copy off still has to put the text on the pasteboard, so the previous contents are restored 400 ms after ⌘V.
- The "History" chip is the "keep transcripts in history" toggle. Off means the pipeline never writes the row.
- Per-tool output config lives in UserDefaults as JSON under `output.<toolID>`; the tool supplies the default via `Tool.defaultOutput`.
- Text-only "Save" writes `<tool> <yyyy-MM-dd HH.mm.ss>.txt`; default folder `~/Movies/Deskpouch` until General exposes it.

## Milestone 3 (done 2026-09-15): history and after-capture actions

- SQLite at `~/Library/Application Support/Deskpouch/history.sqlite`, plain SQLite (no ORM, no CoreData). Table `results`: id, tool_id, created_at, text, file_path, duration, pasted_into.
- `OutputPipeline` configurable per tool: copy, paste, save to folder, reveal in Finder, run shell command, notify, history. Voice default: paste + copy + history. Recorder default (milestone 4): save + copy file + notify + history.
- Panel: chips row on the Voice card (Paste, Copy, History; Notify exists in the pipeline but is not offered for voice, the pill already reports); "Recent" section with the last 5 results (mic tile, copy button re-copies the transcript) and a total count. Hidden while history is empty.
- "Keep transcripts in history" is the History chip, default on.
- Tests on Core: history store round trip and persistence, pipeline ordering and clipboard restore, settings persistence, relative time.
- Not yet: clear history (store has `clear()`, UI lands with General in milestone 5), shell command and save folder editing (config fields exist, no UI).

## Milestone 4 spec: screen recorder

See "Screen recorder tool, v1" above. Emits a `ToolResult` with `fileURL` and `duration`; the pipeline's save/reveal/notify/history already handle files. Recent row shows a dark tile with a duration badge until thumbnails exist.

## Open items
- Default hotkeys for screen recorder.
- Output folder name and location (likely `~/Movies/Deskpouch` for video, transcripts in history only).
- Video quality preset and max length guard.
- "Don't keep transcripts" toggle before any public release.
