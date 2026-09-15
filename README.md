# Deskpouch

Personal macOS menubar app hosting small capture tools. See `PLAN.md` for scope and `design/DESIGN.md` for the visual spec.

## Build

Requires Xcode 26, macOS 15+, Apple Silicon. The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate            # only after editing project.yml
open Deskpouch.xcodeproj     # or:
scripts/run.sh               # xcodebuild Debug + launch
```

Core tests run without Xcode:

```sh
cd Packages/DeskpouchCore && swift test
```

If `xcodebuild` fails with "A required plugin failed to load", run `xcodebuild -runFirstLaunch`.

## Permissions

The hold-to-talk key uses AppKit global event monitors, which need Accessibility access; pasting posts ⌘V through the same grant. Dictation needs Microphone access. The screen recorder needs Screen Recording access (the ⌘⇧6 combo itself is a Carbon hotkey and needs nothing). All are prompted on first use; macOS usually wants the app relaunched after the Screen Recording grant.

Builds are ad-hoc signed by default, so macOS treats every rebuild as a new app and forgets both grants. Run this once to create a stable local signing certificate (approve the Keychain dialogs it triggers):

```sh
scripts/make-dev-cert.sh
```

It writes the identity into `Signing.xcconfig`. Keep that change local.

## Voice language

Parakeet v3 is multilingual and can drift scripts on unknown names. The voice tool passes a language hint that keeps the decoder on one script. It defaults to the system language when supported, otherwise English. Until the options UI lands (milestone 5), change it with:

```sh
defaults write com.constantinchirila.deskpouch voice.language de   # any ISO 639-1 code Parakeet v3 supports
```

The panel's engine line shows the active code, e.g. "Parakeet v3 · EN". Takes effect on the next dictation.

## History and after-capture actions

Every capture that has the History chip on is logged to `~/Library/Application Support/Deskpouch/history.sqlite` (plain SQLite, table `results`). The panel shows the last 5 under Recent with a total count; the copy button puts the transcript back on the clipboard. Delete the file to reset history until the General view lands.

The chips on the Voice card (Paste, Copy, History) are the after-capture actions for that tool, stored as JSON in `defaults` under `output.voice`. Paste with Copy off still uses the pasteboard for ⌘V, then restores what was there. Save to folder, reveal and shell command exist in the pipeline but have no UI yet.

```sh
sqlite3 ~/Library/Application\ Support/Deskpouch/history.sqlite 'select datetime(created_at,"unixepoch"), pasted_into, text from results order by created_at desc limit 5'
defaults delete com.constantinchirila.deskpouch output.voice   # back to the tool defaults
```

## Screen recorder

⌘⇧6 opens the picker: drag a region (⇧ snaps to 16:9, drag inside the selection to move it), or switch to Window or Screen and click the target. Return or the Record button starts; Escape cancels. While recording the menubar shows a pink timer and the pill shows the timer with a Stop button. ⌘⇧6, the menubar icon or Stop ends it; the file is saved to `~/Movies/Deskpouch`, copied to the pasteboard, announced, and logged under Recent (chips on the card change that). Deskpouch's own windows are left out of the recording.

Options have no UI until milestone 5 and live in `defaults`:

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
cd Packages/ToolScreenRecorder && swift test
```

## Design review

Two helpers render the custom UI to PNG so it can be compared against the mocks without clicking through the app:

```sh
# Core components (pill, keycaps, icons, menubar images) via ImageRenderer
cd Packages/DeskpouchCore && DESKPOUCH_SNAPSHOT_DIR=/tmp/snap swift test --filter SnapshotDumpTests

# The live app: shows the pill and the panel for 5 s and dumps both (Recent is seeded with fake rows when empty).
# The panel PNG takes ~10 s: its shadow is blurred on the CPU.
DESKPOUCH_DEMO=pill DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Every pill state, one PNG each. The recording state also logs a hit test: the pill must take clicks, clear pixels must not.
DESKPOUCH_DEMO=states DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# The region picker with a region drawn (needs Screen Recording access), dumped after 2 s and cancelled
DESKPOUCH_DEMO=picker DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# A real 4 s recording of a fixed region, delivered through the real pipeline (writes to ~/Movies/Deskpouch and history)
DESKPOUCH_DEMO=record open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Real Parakeet transcription of a file, no mic, no paste (writes demo-transcript.txt and .png)
say -o /tmp/speech.wav --data-format=LEF32@16000 "Can we move standup to ten"
DESKPOUCH_DEMO=transcribe DESKPOUCH_DEMO_WAV=/tmp/speech.wav DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app
```

Logs: `/usr/bin/log stream --predicate 'subsystem == "com.constantinchirila.deskpouch"' --level debug` (zsh has a `log` builtin that shadows the tool).

Note: ImageRenderer drops a trailing `Text` in an `HStack` on this OS; the in-app dump is the source of truth.

## Layout

```
App/                      thin app target: entry point, shell, status item, menubar panel
Packages/DeskpouchCore/   Tool protocol, theme, components, hotkeys, overlay pill, mic capture, output pipeline, history
Packages/ToolVoice/       VoiceTool and the Parakeet transcriber (FluidAudio)
Packages/ToolScreenRecorder/  ScreenRecorderTool, ScreenCaptureKit recorder, region/window/screen picker
design/                   spec and mocks
```

## Status

- Milestone 1 done: menubar app, Right Option hold shows the listening pill, menubar meter, panel with the Voice card.
- Milestone 2 done: hold to record the mic, Parakeet v3 transcribes locally (model ~600 MB, downloaded to `~/Library/Application Support/FluidAudio` on first launch), transcript is copied and pasted into the frontmost app. Pill shows listening, transcribing, pasted and failure states.
- Milestone 3 done: SQLite history, per-tool after-capture actions (chips on the Voice card), Recent list with re-copy.
- Milestone 4 done: ⌘⇧6 picker (region, window, screen), ScreenCaptureKit recording to mp4 with system audio and optional mic, recording pill and menubar timer, screen card with its chips.
- Next: milestone 5, General view and per-tool options.
