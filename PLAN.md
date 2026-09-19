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

## Status (2026-09-19)

Milestones 1 to 5 (v1) are implemented. Milestones 1 to 3 are verified on the dev machine (milestone 3 with a real dictation landing in Recent). Milestone 5 (options rows and General) is checked against the mocks through `DESKPOUCH_DEMO=options`; its controls still want a hands-on pass (shortcut recording, folder chooser, launch at login). Milestone 4 (screen recorder) is verified on the dev machine: a 4 s region recording through `DESKPOUCH_DEMO=record` produced a 1006x734 H.264 mp4 with a system audio track in `~/Movies/Deskpouch`, put the file on the pasteboard and logged it in history; the pill, panel and picker were checked against the mocks through the demo modes. macOS 15 shows its own "bypass the system private window picker" alert on the first recording (and periodically after); click Allow. `README.md` has build, permissions, and verification instructions.

v2 (see "v2 tools" below): foundation steps 1 to 4 are done (`DeskpouchCapture` package, per-tool switches, `EditorWindowController`, image results and history kinds). `OutputAction.appendToFile` and `Tool.offeredActions` are deferred to plan 08; `OverlayWindow` to plan 03.

Screenshot step 1 (quick capture, package `ToolScreenshot`, ⌘⇧2) is done. Verified on the dev machine through `DESKPOUCH_DEMO=shot` (region 1040x760 pt -> 2080x1520 px), `shot` with `DESKPOUCH_DEMO_SHOT=window` (Calculator: 460x816 px with the shadow off, 684x1040 px with it on (shadow only, cropped on all sides), window body at native size), and `shot-picker` (real picker path: overlay gone after confirm, PNG on the pasteboard byte-identical to the saved file, history row with thumbnail). A real mouse drag was not driven programmatically. `scripts/test.sh` passes (108 tests).

Decisions from the screenshot work:
- Default hotkey ⌘⇧2, not ⌘⇧4: macOS's screenshot shortcut still fires when another app registers ⌘⇧4 (registration succeeds), so both captured.
- The picker returns focus to the previously frontmost app on dismiss, so ⌘V after a capture pastes there instead of into Deskpouch.
- The selection's ring and glow are masked to the outside; the selection shows the screen untouched.
- `StillCapture` sets the output size explicitly (`contentRect`/`rect` times `pointPixelScale`); unset, SCK uses its 1920x1080 default. `contentRect` of a `desktopIndependentWindow` filter is the bare frame, so with the shadow on it requests a 128 pt larger canvas with `scalesToFit` off and crops to the non-transparent bounds (all four sides; the bitmap buffer is top-row first, no flip).
- Copy puts the staged PNG bytes on the pasteboard plus a lazily provided TIFF (lost if the app is killed; Quit resolves it).
- Staging files live in a UUID subfolder of Application Support; with Save off they stay there, like recordings.

Screenshot steps 2 and 3 (pill Annotate button, hover Annotate on screenshot rows, the editor) are done 2026-09-17. Verified through `DESKPOUCH_DEMO=annotate`: captured pill with thumbnail, editor opened from the newest row with an arrow, box, badge, blur and text, export wrote `… annotated.png` beside the original (original kept), PNG on the pasteboard, new history row, editor closed. Renderer checked against a golden PNG; `scripts/test.sh` passes. Not yet driven by hand: real mouse drags, handles, typing text, keyboard shortcuts in the editor.

Decisions from the editor work:
- `ToolResult.followUp` (label plus an action on the delivered file) drives the pill's button, so Trim (05) reuses it. The pill's captured state takes clicks; hovering holds it, leaving restarts a 3 s timer.
- `EditorWindowController` lives in Core and reaches tools through `ToolContext.editor`; exports go back through the shell's `deliver`, so the tool's chips decide copy/save/history. Export writes beside the source and never overwrites (`CaptureNaming.unique`); re-annotating `… annotated.png` numbers the file instead of stacking the suffix. With Save on and the folder unchanged, the pipeline's Save leaves it in place.
- Annotations are stored in image pixels; `AnnotationRenderer` draws both the canvas and the export. Sizes scale with the capture's pixels per point, now written into the PNG as DPI (`ImageWriter.write(pixelsPerPoint:)`); files without DPI assume the main screen's scale.
- Blur averages the whole image into 16 pt blocks once and shows it through a clip per mark, with per-block noise seeded from the mark's id (review 2026-09-17: 6 pt pixelation was reversible for text).
- Review fixes 2026-09-17: an export in flight always delivers its file, and close requests wait for it; the discard prompt takes the keyboard from a text field; the canvas tracks the press explicitly; decode, pixelation and export rendering run off the main actor (`AnnotationRenderer` is `Sendable`, text measured through CoreText by font name); the pill keeps a 160 px thumbnail and drops it once hidden.
- Text is a filled plate in the chosen colour with contrasting ink. Double-click a text mark to retype it; empty deletes it.
- Keys: A arrow, R box, T text, B blur, N number, Delete removes, arrows nudge (Shift 10 pt), Shift while drawing snaps arrows to 45° and boxes to squares, ⌘Z / ⇧⌘Z, ⌘C copies without saving, ⌘S exports and closes, Esc ends text, then clears the selection, then closes. Closing with marks (Esc, ⌘W, close button) asks first: Discard (D), Keep editing (Esc), Export (Return); the prompt says the original is already saved and where. The header reads "original saved" or "marks not exported".
- Picker: a double-click inside the drawn region captures (or starts a recording), same as Return.
- Closing the last editor hands focus back to the app that was in front. Switching Screenshot off closes open Annotate editors; the hover Annotate on screenshot rows stays (decided 2026-09-17).
- One editor window per document (changed 2026-09-17 from "a second replaces the first"): several screenshots can be annotated at once, new windows cascade from the newest, and annotating a file that is already open brings its window forward (`EditorDocument.documentKey`). `EditorWindowController` manages the windows; each is an `EditorSession`.

Text grab (02) is parked (2026-09-17). Color (03) is done 2026-09-17: package `ToolColor`, ⌘⇧9, loupe on an
interactive `OverlayWindow`, five formats, Tailwind v4 hints, colour rows in Recent and History with a swatch
tile. Verified through `DESKPOUCH_DEMO=color DESKPOUCH_DEMO_CLICK=1`, which posts real input: ⌘⇧9 opened the
loupe, a 40 pt mouse move and a Right Arrow moved the sample 80 px and then 1 px, a real click copied
`#f59e0c` (an amber `#f59e0b` PNG shown in Preview; macOS's own `screencapture`, converted to sRGB the same way,
reads `#f59e0c` too, so the one unit is the display round trip, not us) and logged a `color` row. `scripts/test.sh`
passes (173 tests).

Decisions from the colour work:
- The loupe samples one capture per display, taken when the cursor first reaches that display, not a capture per
  mouse move (`SCScreenshotManager` is tens of ms). The screen it shows is therefore frozen at open time.
- Captures are redrawn into an 8-bit sRGB buffer off the main actor (`PixelBuffer`), which is what converts from
  the display's P3 space; sampling is then an array read.
- `OverlayWindow` (Core, from plan 00) grew an `interactive` flag: click-through for the marks in plan 06, and
  key-taking with `ignoresMouseEvents = false` for the loupe (clear pixels pass clicks through otherwise).
- Keyboard only reaches the loupe while the app is active, and `NSApp.activate()` only takes effect off a real
  key press: a demo that opens the loupe programmatically gets mouse events but no keys. The real ⌘⇧9 path is fine.
- Arrow nudges warp the hidden cursor onto the new pixel's centre, so the next mouse move carries on from there.
- The Tailwind table is generated from tailwindcss 4.3.3's `theme.css` (26 hues now, not the 22 the plan assumed;
  mauve, olive, mist and taupe were added), kept as its own OKLCH triples and compared unclamped in Lab: most v4
  entries sit outside sRGB, so an exact match is rare (amber-500 is ΔE 4.8 from `#f59e0b`).
- Conversions (OKLab/OKLCH, Lab, HSL, ΔE2000) are tested against culori 4 reference values and the Sharma ΔE2000
  table; the `oklch` string keeps 3 decimals (the plan's 2 lose too much chroma).
- A colour row in Recent and History unfolds on click into every format of that colour, one copyable line each
  (the user asked for this on 2026-09-17); the open row lives in `ShellState.expandedColor`, so one is open at a
  time and the lists' refreshes do not close it.
- History rows gained a `meta` TEXT column (`ResultMeta`, JSON): the colour tool writes the exact sRGB there,
  because the row's text is only the copied format. The same column carries `display` and `rect` for the
  screenshot work due before diff (04), so that migration is already done. Older databases get the column on open
  (tested against a hand-built old-schema file).
- `RGBColor` had to become `SRGBColor`: SwiftUI exports a type of that name, so the app target could not resolve
  ours.
- Not verified by hand yet: Escape and Return in the loupe, a second display, and the loupe over a non-P3 screen.

`capture_rect` (due before diff, 04) is done 2026-09-19: every screenshot row now carries `display` and `rect` in
`meta` (`PickerSelection.captureMeta(screens:)` in `DeskpouchCapture`, pure and tested). Verified through
`DESKPOUCH_DEMO=shot` (row meta `{"rect":[160,140,1040,760],"display":1}`, file 2080x1520 px) and
`DESKPOUCH_DEMO_SHOT=window` (bare frame `[444,402,920,464]`). `scripts/test.sh` passes. Diff (04) is parked (2026-09-19: not used often enough); the
meta stays, it is cheap and 04 needs it if it comes back.

Trim + GIF (05) is done 2026-09-19 (`ToolScreenRecorder/Trim`). Verified through `DESKPOUCH_DEMO=trim`: a real 4.3 s
recording, the pill's Trim pressed, 1 s cut off each side, exported as `… trimmed.mp4` (2.3 s by Spotlight's
duration, beside the original, original kept, history row, copied), then Trim from the recording's row exported as
`… trimmed.gif` (960x700, 29 frames for 2.3 s). Editor and pill checked from the demo's PNGs. `scripts/test.sh`
passes (201 tests). Not driven by hand yet: real drags on the handles and the playhead, Space / I / O / arrows,
Copy, the discard prompt, the GIF-over-15-s warning. Next: gallery (10), grilled first.

Decisions from the trim work:
- The row's hover button is one slot (`PanelActions.edit`, `HistoryItem.editLabel`): Annotate for a screenshot, Trim
  for a recording. GIF rows get no Trim.
- The pill's tile shows the recording's first frame (the shell reads it, `ToolResult.image` stays nil so the
  pipeline does not treat the result as an image), and the button's glyph follows the label ("Trim").
- GIF frames: the reader decodes at the output size (max 960 wide, never upscaled); each twelfth of a second shows
  the last frame at or before it, and a still stretch becomes one image with a longer delay, so screen recordings
  with idle parts stay small. 12 distinct frames a second at most.
- The GIF size estimate is measured, not guessed: up to 1 s from the in point is written to a temporary file
  (300 ms after the last change) and scaled by length. The mp4 estimate is the file's size by share of length.
- Handles snap to 0.1 s and stop 0.5 s short of each other; I and O take the playhead unsnapped; arrows step one
  frame (Shift: ten). Seeks are exact and coalesced: a drag only waits for the newest.
- Closing with a trim set asks first, like Annotate. Copy writes the cut into Application Support and puts that file
  on the pasteboard (the button says Copied before a long GIF has finished writing; known).
- A GIF of the whole recording is named `… .gif`, not `… trimmed.gif`.

Decisions from the `capture_rect` work:
- The rect is display-local points with a top-left origin, which is what a region `StillCapture` takes back.
- A window is stored as its bare frame (no shadow), clipped to the display holding most of it; Recapture of a
  window row is therefore a region capture of where the window was, and with the shadow on the two files differ in
  size (diff's "sizes differ" letterbox covers it, or Recapture can ignore the shadow; decide in 04).
- A window on no known display writes no meta, and so do annotated exports and rows from before this: Recapture
  has to be hidden for rows without it.

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

0. [Foundation](docs/plans/00-foundation.md) (done: steps 1, 2 and 4 on 2026-09-16, step 3's `EditorWindowController` with screenshot on 2026-09-17; `OverlayWindow` for the loupe moves to 03): `DeskpouchCapture` package (picker and still capture move out of the recorder), image results and history kinds in the pipeline, per-tool on/off switches in General (off hides the row and frees the hotkey), hotkey inventory (⌘⇧6 and ⌘⇧2 have named `KeyCombo` statics so far).
1. [Screenshot + annotate](docs/plans/01-screenshot.md), ⌘⇧2: quick capture (step 1, done 2026-09-16, package `ToolScreenshot`), pill Annotate button (step 2), editor with arrow/box/text/blur/badge (step 3); both done 2026-09-17.
2. [Text grab](docs/plans/02-text-grab.md), ⌘⇧8: region OCR through Vision, lines kept, pasted. **Parked 2026-09-17**; color goes next.
3. [Color](docs/plans/03-color.md), ⌘⇧9: loupe, click copies hex (format option), Tailwind name as hint. **Done 2026-09-17.**
4. [Screenshot diff](docs/plans/04-diff.md): two history rows → Compare; Recapture same region; slider / onion / pixels. **Parked 2026-09-19** (`capture_rect` is in place).
5. [Trim + GIF](docs/plans/05-trim-gif.md): pill Trim button, passthrough MP4, capped GIF. **Done 2026-09-19.**
6. [Demo polish](docs/plans/06-demo-polish.md): click ripple, keystroke chip, presenter mode; exclusion becomes per-window. Webcam bubble later.
7. [Meeting](docs/plans/07-meeting.md), ⌘⇧M: system audio + mic as Me/Them, live 30 s chunks, markdown into the vault. Moves the transcribers into a `DeskpouchSpeech` package.
8. [Voice note](docs/plans/08-voice-note.md), Right Command hold: append to the daily note, no paste. **Parked 2026-09-19**: Voice already pastes into Obsidian, and an unstructured append-only list is a dumping ground; revive only with a way to structure it.
9. [Image convert](docs/plans/09-image-convert.md): drop on row or Finder service, WebP/PNG/JPEG beside the source.
10. [Gallery](docs/plans/10-gallery.md) (added and grilled 2026-09-19): one master-detail window over history (list left, large preview right), replaces the panel's History view; delete moves the file to the Trash, multi-select, starred, date presets, drag out; the app turns regular (Dock, ⌘Tab) while a real window is open. Package `DeskpouchGallery`. Step 0 (activation-policy spike, on the editors) is done 2026-09-19: works, no menu-bar quirk. Step 1 (Core: `HistoryQuery`, counts by kind, `starred`, batch delete handing back files) is done the same day, 211 tests pass. Next: step 2, the window.

Package rule after 0 and 7: tools import Core, Capture and Speech only; those three never import a tool; Core imports neither of the other two.

## Open items
- Fifteen-plus tools: the list still grows 52 pt per tool; revisit (grouping, or a compact mode) when it happens.
- Sparkle and signed builds before anything is shared; "Check for updates" is disabled until then.
- Panel content taller than the screen (many rows expanded on a small display) is clipped; no scrolling yet.
- Custom vocabulary, toggle mode and LLM cleanup for voice remain out of scope.
