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

The hold-to-talk key uses AppKit global event monitors, which need Accessibility access; pasting posts ⌘V through the same grant. Dictation needs Microphone access. Both are prompted on first use.

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

## Design review

Two helpers render the custom UI to PNG so it can be compared against the mocks without clicking through the app:

```sh
# Core components (pill, keycaps, icons, menubar images) via ImageRenderer
cd Packages/DeskpouchCore && DESKPOUCH_SNAPSHOT_DIR=/tmp/snap swift test --filter SnapshotDumpTests

# The live app: shows the pill and the panel for 5 s and dumps both
DESKPOUCH_DEMO=pill DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Every pill state, one PNG each
DESKPOUCH_DEMO=states DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app

# Real Parakeet transcription of a file, no mic, no paste (writes demo-transcript.txt and .png)
say -o /tmp/speech.wav --data-format=LEF32@16000 "Can we move standup to ten"
DESKPOUCH_DEMO=transcribe DESKPOUCH_DEMO_WAV=/tmp/speech.wav DESKPOUCH_DEMO_OUT=/tmp/snap open build/DerivedData/Build/Products/Debug/Deskpouch.app
```

Logs: `log stream --predicate 'subsystem == "com.constantinchirila.deskpouch"' --level debug`.

Note: ImageRenderer drops a trailing `Text` in an `HStack` on this OS; the in-app dump is the source of truth.

## Layout

```
App/                      thin app target: entry point, shell, status item, menubar panel
Packages/DeskpouchCore/   Tool protocol, theme, components, hotkeys, overlay pill, mic capture, paste pipeline
Packages/ToolVoice/       VoiceTool and the Parakeet transcriber (FluidAudio)
design/                   spec and mocks
```

## Status

- Milestone 1 done: menubar app, Right Option hold shows the listening pill, menubar meter, panel with the Voice card.
- Milestone 2 done: hold to record the mic, Parakeet v3 transcribes locally (model ~600 MB, downloaded to `~/Library/Application Support/FluidAudio` on first launch), transcript is copied and pasted into the frontmost app. Pill shows listening, transcribing, pasted and failure states.
- Next: milestone 3, history and configurable after-capture actions.
