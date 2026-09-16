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
    DeskpouchCapture/     picker, capture geometry, ScreenCaptureKit content lookup; depends on Core only
    ToolVoice/            depends on Core only
    ToolScreenRecorder/   depends on Core and Capture
```

Rules: tools never import each other. Core never imports a tool or Capture; Capture never imports a tool. Tests live per package, mostly on Core (pipeline, history, hotkey conflicts). Capture code is not unit tested.

### Distribution
- Unsigned local builds for now.
- Developer ID + notarization + Sparkle when a build is first shared with a teammate or sold.
- Never App Store (sandbox blocks paste, system audio, hotkeys).

### Visible surfaces, v1
Design direction settled 2026-09-14: "Mint ground, amber accent", custom chrome. Full spec with tokens and components in `design/DESIGN.md`. Mocks in `design/mocks/Final*.dc.html`.

- One floating panel drops from the menubar icon and is the whole app. No Settings window, no dashboard, no library.
- Panel (layout v2, 2026-09-15): header, a "Tools" list with one 52 pt row per tool (tile, name, one-line status, shortcut keycaps, chevron; amber while listening, pink while recording), Recent list (last 5, tile per item), footer with General and Quit. A row pushes the tool's own view: back chevron, its card with meter and chips, and its option rows always open. Replaced the v1 accordion of cards, whose height grew with every tool and every expanded card; tabs were mocked and dropped because eight tools become unlabeled icons. Mocks: `design/mocks/List*.dc.html`.
- General is a second view inside the same panel behind a back chevron: launch at login, sounds, menubar timer, history toggles, clear history, permissions status, version and updates.
- Pill: top-center under the menubar (was bottom-center until 2026-09-15; it sat on top of chat inputs and terminals), non-activating. Listening (bar meter), transcribing (grows into a card, text types in), pasted (undo hint), recording (timer, dims, Stop).
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

Milestones 1 to 5 are implemented. Milestones 1 to 3 are verified on the dev machine (milestone 3 with a real dictation landing in Recent). Milestone 5 (options rows and General) is checked against the mocks through `DESKPOUCH_DEMO=options`; its controls still want a hands-on pass (shortcut recording, folder chooser, launch at login). Milestone 4 (screen recorder) is verified on the dev machine: a 4 s region recording through `DESKPOUCH_DEMO=record` produced a 1006x734 H.264 mp4 with a system audio track in `~/Movies/Deskpouch`, put the file on the pasteboard and logged it in history; the pill, panel and picker were checked against the mocks through the demo modes. macOS 15 shows its own "bypass the system private window picker" alert on the first recording (and periodically after); click Allow. Next: whatever comes after v1 (see "Open items"). `README.md` has build, permissions, and verification instructions.

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
- Key combos (⌘⇧6) go through Carbon `RegisterEventHotKey`: no Accessibility dependence and the press never reaches the frontmost app. Modifier holds stay on the NSEvent monitors. `Tool` grew `pressKey` and `keyPressed()` with no-op defaults, plus `ToolContext.report(_:from:)` so a tool can tell the shell it is recording.
- Keycaps print ⌘⇧6 (mock order), not Apple's ⇧⌘6.
- Recordings are written by `SCRecordingOutput` into a temp folder; the pipeline's Save moves the file, and Copy file runs after Save for file results so the pasteboard points at the final path. Save off means the file stays in temp (system-purged), for "paste it into Slack and forget it".
- The recording pill keeps its Stop button (Visible surfaces spec wins over the older "no floating controls" line); Deskpouch's own windows are excluded from display captures through `SCContentFilter(display:excludingApplications:)`, so the pill never appears in the file. The app object for that has to come from `SCShareableContent.currentProcess`: the general content list leaves Deskpouch out (no regular windows) and the exclusion silently did nothing until 2026-09-15. Window captures use `desktopIndependentWindow`.
- Menubar click while recording stops the recording instead of opening the panel.

## Milestone 3 (done 2026-09-15): history and after-capture actions

- SQLite at `~/Library/Application Support/Deskpouch/history.sqlite`, plain SQLite (no ORM, no CoreData). Table `results`: id, tool_id, created_at, text, file_path, duration, pasted_into.
- `OutputPipeline` configurable per tool: copy, paste, save to folder, reveal in Finder, run shell command, notify, history. Voice default: paste + copy + history. Recorder default (milestone 4): save + copy file + notify + history.
- Panel: chips row on the Voice card (Paste, Copy, History; Notify exists in the pipeline but is not offered for voice, the pill already reports); "Recent" section with the last 5 results (mic tile, copy button re-copies the transcript) and a total count. Hidden while history is empty.
- "Keep transcripts in history" is the History chip, default on.
- Tests on Core: history store round trip and persistence, pipeline ordering and clipboard restore, settings persistence, relative time.
- Not yet: clear history (store has `clear()`, UI lands with General in milestone 5), shell command and save folder editing (config fields exist, no UI).

## Milestone 4 (done 2026-09-15): screen recorder

Decisions for the open items, taken from the Final mocks:
- Hotkey ⌘⇧6. Opens the picker; pressed again it cancels the picker or stops the recording.
- Output folder `~/Movies/Deskpouch`, file `Recording yyyy-MM-dd HH.mm.ss.mp4`.
- Quality "High, 1080p" at 60 fps, H.264 in mp4: a full-screen recording is scaled to fit 1080 rows and regions and windows use the same pixels-per-point. "Full" keeps native pixels. Options live in `defaults` under `screen.*` until milestone 5.
- Max length 30 minutes, then the recording stops and is delivered normally.
- System audio on and microphone off by default; the picker's round toggles change both and persist.

Package `ToolScreenRecorder`: `ScreenRecorderTool` (phases: idle, picking, starting, recording, stopping), `ScreenRecorder` (one SCStream plus `SCRecordingOutput`), `CaptureGeometry` (scaling, drag rects, aspect snap), `PickerModel` (pure state, tested) with `PickerWindowController` (one borderless window per screen at screen-saver level) and the SwiftUI picker views. Region mode: drag, drag inside to move, ⇧ snaps 16:9, Return or Record starts. Window and screen modes: hover highlights, click starts. Escape cancels.

Recent rows for files: a frame from the file (generated on demand, `ThumbnailCache`, dark tile while loading or when the file is gone) with a duration badge; double-click reveals in Finder, the button copies the file.

Leftovers closed 2026-09-15: thumbnails, panel spring-in and fade-out (card expand motion lands with the options rows in milestone 5). "Don't keep transcripts" is the History chip on the Voice card, so that open item is closed too.

## Milestone 5 (done 2026-09-15): General view and per-tool options

- Core gained the row controls from DESIGN.md: `OptionRow`, `OptionRows`, `OptionsGroup`, `ToggleSwitch`, `RowButton`, `PopupButton`/`PopupPicker` with one in-panel dropdown (`PopupController`, drawn by the `popupHost` modifier under the button's anchor, scrolls past 8 rows), and `ShortcutRecorder` (records a modifier hold or a key combo through a local monitor, Escape cancels, combos need ⌘, ⌥ or ⌃).
- Cards expand in place under "Options" (chevron turns). Voice: model (size from the FluidAudio folder), language, microphone (Core Audio device list; `MicRecorder.deviceUID` sets the audio unit's device), shortcut. Screen: save folder (NSOpenPanel, the panel holds itself open meanwhile), quality, frame rate, system audio, microphone, shortcut. Changing a shortcut re-registers the hotkey; hold key is `voice.holdKey`, combo is `screen.hotkey`, mic is `voice.microphone`.
- General view behind the back chevron (Escape also goes back): launch at login (SMAppService), sounds (Tink/Pop system sounds on start and stop), menubar timer (off leaves just the dot), keep history (off strips the history action before delivery; detail shows count and the size of the files on disk), transcripts in history (the voice History chip), clear history with inline confirm, permissions summary (click opens the first missing one in System Settings), version with a disabled "Check for updates" until Sparkle.
- The panel window spans from the status item to the bottom of the screen and the content is top-aligned, so switching views needs no window resize. Clicks on the empty part of the window close the panel.
- Panel snapshots use a ScreenCaptureKit window screenshot (`WindowSnapshot`); the view cache went blank once the root had scale and opacity effects. The screenshot can raise the system capture alert, so the options demo holds the panel open.

## History view (done 2026-09-15)

"All N ›" in the Recent header pushes the History view (mock: `design/mocks/History*.dc.html`): search over transcripts and file names (SQLite LIKE with escaped wildcards), All / Voice / Recordings filter (by tool id), rows grouped by day (`DayGroup`: Today, Yesterday, "Tue 8 Sep") with clock times, 20 rows per page and "Show older · N more", delete on hover (removes the log row, never the file). The list scrolls inside the panel; the controller tells the view how tall it may be. Core: `HistoryStore.items(matching:toolID:limit:offset:)` and `count(matching:toolID:)`, `Segmented`, `SearchField`, tests for the query and the day labels.

## Voice engines (2026-09-15)

The Model row offers two engines behind the `Transcriber` protocol: Parakeet v3 (FluidAudio, about 470 MB download, best accuracy, 25 European languages) and Apple Speech (`AppleTranscriber`: the Speech framework with `requiresOnDeviceRecognition`, nothing to download, less accurate, languages follow the dictation assets installed in macOS). `voice.engine` persists the choice; Parakeet only downloads when it is the selected engine, and with Apple selected a "Remove download" button deletes the Parakeet folder. Apple Speech needs the Speech Recognition grant (prompted on first use) and Dictation turned on in System Settings › Keyboard; with it off, macOS answers kLSRErrorDomain 201 and the pill says so. Other local models under 500 MB were assessed and not added: Parakeet TDT-CTC 110M (English, lighter, less accurate) and SenseVoice small (Asian languages) are one day's work inside FluidAudio if a need appears; WhisperKit's small models lose to Parakeet in English; Apple's SpeechAnalyzer needs macOS 26.

## v2 tools (planned 2026-09-16)

Nine additions, grilled and decided; one plan per tool under `docs/plans/`. Build order, foundation first:

0. [Foundation](docs/plans/00-foundation.md) (step 1, the Capture package move, done 2026-09-16; `PickerStyle`, `StillCapture`, `ImageWriter`, `OverlayWindow` land with their first tool): `DeskpouchCapture` package (picker and still capture move out of the recorder), `EditorWindowController` in Core, image results and history kinds in the pipeline, per-tool on/off switches in General (off hides the row and frees the hotkey), hotkey inventory.
1. [Screenshot + annotate](docs/plans/01-screenshot.md), ⌘⇧4: quick capture, pill Annotate button, editor with arrow/box/text/blur/badge.
2. [Text grab](docs/plans/02-text-grab.md), ⌘⇧8: region OCR through Vision, lines kept, pasted.
3. [Color](docs/plans/03-color.md), ⌘⇧9: loupe, click copies hex (format option), Tailwind name as hint.
4. [Screenshot diff](docs/plans/04-diff.md): two history rows → Compare; Recapture same region; slider / onion / pixels.
5. [Trim + GIF](docs/plans/05-trim-gif.md): pill Trim button, passthrough MP4, capped GIF.
6. [Demo polish](docs/plans/06-demo-polish.md): click ripple, keystroke chip, presenter mode; exclusion becomes per-window. Webcam bubble later.
7. [Meeting](docs/plans/07-meeting.md), ⌘⇧M: system audio + mic as Me/Them, live 30 s chunks, markdown into the vault. Moves the transcribers into a `DeskpouchSpeech` package.
8. [Voice note](docs/plans/08-voice-note.md), Right Command hold: append to the daily note, no paste.
9. [Image convert](docs/plans/09-image-convert.md): drop on row or Finder service, WebP/PNG/JPEG beside the source.

Package rule after 0 and 7: tools import Core, Capture and Speech only; those three never import a tool; Core imports neither of the other two.

## Open items
- Fifteen-plus tools: the list still grows 52 pt per tool; revisit (grouping, or a compact mode) when it happens.
- Sparkle and signed builds before anything is shared; "Check for updates" is disabled until then.
- Panel content taller than the screen (many rows expanded on a small display) is clipped; no scrolling yet.
- Custom vocabulary, toggle mode and LLM cleanup for voice remain out of scope.
