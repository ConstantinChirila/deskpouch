# Deskpouch

Personal macOS menubar app hosting small capture tools. See `PLAN.md` for scope and `design/DESIGN.md` for the visual spec.

## Build

Requires Xcode 26, macOS 15+, Apple Silicon. The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate            # only after editing project.yml
open Deskpouch.xcodeproj     # or:
scripts/run.sh               # xcodebuild Debug + launch
```

Package tests run without Xcode (CI runs the same script on every push):

```sh
scripts/test.sh
```

If `xcodebuild` fails with "A required plugin failed to load", run `xcodebuild -runFirstLaunch`.

## Permissions

The hold-to-talk key uses AppKit global event monitors, which need Accessibility access; pasting posts ⌘V through the same grant. Dictation needs Microphone access. The screen recorder and the screenshot tool both need Screen Recording access (the ⌘⇧6 and ⌘⇧2 combos themselves are Carbon hotkeys and need nothing). All are prompted on first use; macOS usually wants the app relaunched after the Screen Recording grant.

Builds are ad-hoc signed by default, so macOS treats every rebuild as a new app and forgets both grants. Run this once to create a stable local signing certificate (approve the Keychain dialogs it triggers):

```sh
scripts/make-dev-cert.sh
```

It writes the identity into `Signing.local.xcconfig`, which is git-ignored; `Signing.xcconfig` stays ad-hoc for everyone else.

## Voice engine

The Model row in the Voice view picks the engine: Parakeet v3 (downloaded once, about 470 MB, best accuracy) or Apple Speech (macOS's on-device recognition, nothing to download, less accurate; asks for Speech Recognition access on first use, and needs Dictation turned on in System Settings › Keyboard, which also installs the on-device language). With Apple Speech selected, "Remove download" deletes the Parakeet files. From the shell: `defaults write com.constantinchirila.deskpouch voice.engine apple` (or `parakeet`).

## Voice language

Parakeet v3 is multilingual and can drift scripts on unknown names. The voice tool passes a language hint that keeps the decoder on one script. It defaults to the system language when supported, otherwise English. Change it in the Voice view (click the Voice row in the panel; the microphone and the hold key are there too), or with:

```sh
defaults write com.constantinchirila.deskpouch voice.language de   # any ISO 639-1 code Parakeet v3 supports
```

The panel's engine line shows the active code, e.g. "Parakeet v3 · EN". Takes effect on the next dictation.

## History and after-capture actions

Every capture that has the History chip on is logged to `~/Library/Application Support/Deskpouch/history.sqlite` (plain SQLite, table `results`). The panel shows the last 5 under Recent with a total count; the copy button puts the transcript back on the clipboard, double-click reveals a recording in Finder. The "All N ›" link in the Recent header opens History: search, an All / Voice / Recordings filter, rows grouped by day, "Show older" for the next page, and a delete button on hover that removes the row and keeps the file. General (footer of the panel) has the global "Keep history" switch, the count and size, "Clear…", and the pill position (top under the menubar, or bottom above the Dock).

The chips in the Voice view (Paste, Copy, History) are the after-capture actions for that tool, stored as JSON in `defaults` under `output.voice`. Paste with Copy off still uses the pasteboard for ⌘V, then restores what was there. Save to folder, reveal and shell command exist in the pipeline but have no UI yet.

```sh
sqlite3 ~/Library/Application\ Support/Deskpouch/history.sqlite 'select datetime(created_at,"unixepoch"), pasted_into, text from results order by created_at desc limit 5'
defaults delete com.constantinchirila.deskpouch output.voice   # back to the tool defaults
```

## Screen recorder

⌘⇧6 opens the picker: drag a region (⇧ snaps to 16:9, drag inside the selection to move it), or switch to Window or Screen and click the target. Return or the Record button starts; Escape cancels. While recording the menubar shows a pink timer and the pill shows the timer with a Stop button. ⌘⇧6, the menubar icon or Stop ends it; the file is saved to `~/Movies/Deskpouch`, copied to the pasteboard, announced, and logged under Recent (chips on the card change that). Deskpouch's own windows are left out of the recording.

Options live in the tool's view (click its row in the panel): folder, quality, frame rate, system audio, microphone, shortcut. The same values are in `defaults` for scripting:

```sh
defaults write com.constantinchirila.deskpouch screen.quality full      # high (fits 1080p, default) or full (native pixels)
defaults write com.constantinchirila.deskpouch screen.fps 30            # 30 or 60 (default)
defaults write com.constantinchirila.deskpouch screen.systemAudio -bool false
defaults write com.constantinchirila.deskpouch screen.microphone -bool true
defaults write com.constantinchirila.deskpouch screen.maxMinutes 10     # auto-stop, default 30, 0 disables
defaults write com.constantinchirila.deskpouch screen.cursor -bool false
```

Recorder tests run without Xcode:

```sh
swift test --package-path Packages/DeskpouchCapture
swift test --package-path Packages/ToolScreenRecorder
```

## Screenshot

⌘⇧2 opens the same picker in its mint "still" look: drag a region, or switch to Window or Screen and click the target. A selection captures immediately, no separate start button. Annotate (arrow, box, text, blur, badge) is not built yet, so the capture goes straight through the pipeline: copied to the pasteboard as an image, saved to `~/Pictures/Deskpouch`, and logged with a thumbnail. The default is ⌘⇧2, not ⌘⇧2: macOS's own screenshot shortcut still fires when another app registers ⌘⇧2, so both would capture.

Options live in the tool's view: scale (2x native, the default, or 1x downsampled), save folder, whether a window capture keeps the macOS drop shadow, shortcut.

```sh
defaults write com.constantinchirila.deskpouch shot.scale x1            # native (default, 2x on Retina) or x1
defaults write com.constantinchirila.deskpouch shot.windowShadow -bool false
```

Screenshot tests run without Xcode:

```sh
swift test --package-path Packages/ToolScreenshot
```

## Design review

Two helpers render the custom UI to PNG so it can be compared against the mocks without clicking through the app:

```sh
# Core components (pill, keycaps, icons, menubar images) via ImageRenderer
cd Packages/DeskpouchCore && DESKPOUCH_SNAPSHOT_DIR=/tmp/snap swift test --filter SnapshotDumpTests

# The live app: shows the pill and the panel for 5 s and dumps both (Recent is seeded with fake rows when empty).
# The panel PNG is a ScreenCaptureKit screenshot of the window, so it needs the Screen Recording grant.
DESKPOUCH_DEMO=pill DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Every pill state, one PNG each. The recording state also logs a hit test: the pill must take clicks, clear pixels must not.
DESKPOUCH_DEMO=states DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# The main list, the Voice view, the Record view with the quality dropdown open, General, and History, one PNG each
DESKPOUCH_DEMO=options DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# The region picker with a region drawn (needs Screen Recording access), dumped after 2 s and cancelled
DESKPOUCH_DEMO=picker DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# A real 4 s recording of a fixed region, delivered through the real pipeline (writes to ~/Movies/Deskpouch and history)
DESKPOUCH_DEMO=record open build/DerivedData/Build/Products/Debug/Deskpouch.app

# A real screenshot of a fixed region, no picker, delivered through the real pipeline (writes to ~/Pictures/Deskpouch and history)
DESKPOUCH_DEMO=shot open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Same, but captures the frontmost normal window of another app instead (open one first, e.g. `open ~` for Finder)
open ~
DESKPOUCH_DEMO=shot DESKPOUCH_DEMO_SHOT=window open build/DerivedData/Build/Products/Debug/Deskpouch.app

# The real ⌘⇧2 flow, not the shortcut above: keyPressed() opens the picker, a region is drawn through the same
# PickerModel calls a drag uses, and confirm() is the call the Return key and the toolbar's Capture button make
# (so pickerFinished, dismiss and capture all run for real). Logs whether the picker's windows are gone after
# capture and whether the pasteboard has an image; with DESKPOUCH_DEMO_OUT also dumps a mid-selection snapshot.
DESKPOUCH_DEMO=shot-picker DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Screenshot, captured pill (Annotate), then the editor opened from the newest screenshot row with sample marks and
# exported through the pipeline. Logs whether `… annotated.png` sits beside the original, the original is kept and
# the pasteboard has a PNG; with DESKPOUCH_DEMO_OUT writes app-pill-captured.png and app-editor.png.
DESKPOUCH_DEMO=annotate DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Presses the captured pill's Annotate 5 s after launch; bring another app to the front first (e.g. `open -a Finder`
# at 3 s) to check the editor still opens in front and takes the keyboard (logs `editor active=… key=…`)
DESKPOUCH_DEMO=annotate-pill open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Real Parakeet transcription of a file, no mic, no paste (writes demo-transcript.txt and .png)
say -o /tmp/speech.wav --data-format=LEF32@16000 "Can we move standup to ten"
DESKPOUCH_DEMO=transcribe DESKPOUCH_DEMO_WAV=/tmp/speech.wav DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app
```

Logs: `/usr/bin/log stream --predicate 'subsystem == "com.constantinchirila.deskpouch"' --level debug` (zsh has a `log` builtin that shadows the tool).

Note: ImageRenderer drops a trailing `Text` in an `HStack` on this OS; the in-app dump is the source of truth.

## Branding

The app icon is `App/Resources/AppIcon.icns`. Rebuild it from the asset pack with `iconutil --convert icns` on an iconset holding the 16 to 512 pt sizes at 1x and 2x; the Xcode asset catalog route silently drops sizes with this toolchain. The panel's amber mark lives in `Packages/DeskpouchCore/Sources/DeskpouchCore/Resources/Brand`; the menubar glyph is drawn in code (`MenubarGlyph`), and the snapshot test dumps every candidate into dark and light menubar strips.

## Layout

```
App/                      thin app target: entry point, shell, status item, menubar panel
Packages/DeskpouchCore/   Tool protocol, theme, components, hotkeys, overlay pill, mic capture, output pipeline, history
Packages/ToolVoice/       VoiceTool and the Parakeet transcriber (FluidAudio)
Packages/DeskpouchCapture/    region/window/screen picker, capture geometry, still capture, shareable content lookup
Packages/ToolScreenRecorder/  ScreenRecorderTool, ScreenCaptureKit recorder
Packages/ToolScreenshot/      ScreenshotTool, quick region/window/screen capture
design/                   spec and mocks
```

## Status

- Milestone 1 done: menubar app, Right Option hold shows the listening pill, menubar meter, panel with the Voice card.
- Milestone 2 done: hold to record the mic, Parakeet v3 transcribes locally (model ~600 MB, downloaded to `~/Library/Application Support/FluidAudio` on first launch), transcript is copied and pasted into the frontmost app. Pill shows listening, transcribing, pasted and failure states.
- Milestone 3 done: SQLite history, per-tool after-capture actions (chips on the Voice card), Recent list with re-copy.
- Milestone 4 done: ⌘⇧6 picker (region, window, screen), ScreenCaptureKit recording to mp4 with system audio and optional mic, recording pill and menubar timer, screen card with its chips.
- Milestone 5 done: per-tool views with options (model, language, microphone, folder, quality, frame rate, audio, shortcuts), General view (launch at login, sounds, menubar timer, history switches and clear, permissions, version). Panel layout v2: a list of tools that opens into each tool's view.
- v1 done; v2 tools (see `PLAN.md`) in progress. Foundation (Capture package, tool switches, image results and history kinds) done. Screenshot step 1 (⌘⇧2 quick capture) done; Annotate (pill button, editor) is next.
