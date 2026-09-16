# 07 Meeting recorder

Package `ToolMeeting`, tool id `meeting`, row "Meeting", hotkey ⌘⇧M. Depends on 00 and on `ToolVoice`'s transcribers. Since tools may not import each other, `ParakeetTranscriber` and `AppleTranscriber` move to a new package `DeskpouchSpeech` (Core + FluidAudio) that both ToolVoice and ToolMeeting import. Rule: "tools import Core, Capture and Speech only".

## Decisions
- Start/stop: ⌘⇧M, the tool row's button, or the menubar icon while running. Menubar shows the record timer like the screen recorder; the two cannot run at once (second start is refused with a pill message).
- Audio: two streams. System audio via an audio-only `SCStream` (`capturesAudio`, `excludesCurrentProcessAudio`, video size 2x2 and dropped) = **Them**. Microphone via `MicRecorder` (already in Core) = **Me**. Both resampled to 16 kHz mono Float32.
- Live chunking: every 30 s, or at 1.5 s of silence after 15 s, each stream's buffer goes to the transcriber with the voice language hint. Results append as lines `[HH:mm:ss] Me: …` / `[HH:mm:ss] Them: …`, merged by start time. Stop flushes the remainder; the transcript is ready within seconds.
- No diarisation inside Them; no LLM summary. Filler filter off for meetings.
- Output: `Meeting yyyy-MM-dd HH.mm.md` with a front matter block (date, duration, title) and the lines, saved to the option folder (default: `Meetings` inside the Obsidian vault, chosen via folder picker and stored as a security-scoped bookmark is not needed, app is unsandboxed). Row in history (kind meeting, text = transcript, file = md). Chips: Save / Copy / Keep audio / History. Keep audio writes `.m4a` (AAC, both streams mixed) beside the md.
- Title: pill while recording shows timer and an editable title field; empty title falls back to the frontmost app name at start (e.g. "zoom.us").
- Pill state `.recording(detail:)` reused with "Meeting · 12:03 · 1.2k words".

## Structure
```
DeskpouchSpeech/            ParakeetTranscriber, AppleTranscriber, VoiceEngine (moved)
ToolMeeting/
  MeetingTool.swift         phases idle/starting/recording/stopping; owns both capturers
  SystemAudioCapture.swift  SCStream audio-only → 16 kHz buffers
  Chunker.swift             pure: silence detection + 30 s cap → chunk boundaries. Tested.
  TranscriptAssembler.swift pure: merge Me/Them segments by time → markdown. Tested.
  MeetingSettings.swift     folder, keepAudio, key (`meeting.*`)
```

## Tests
Chunker with synthetic level arrays; Assembler ordering and formatting; front matter.

## Verify
Play a YouTube talk at low volume while talking into the mic for 60 s: md has both labels, timestamps ascend, audio file exists when the chip is on.

## Risks
- Parakeet throughput on long chunks is fine (real-time factor well under 0.1 on M-series), but two streams double it; if the Neural Engine queue backs up, drop to 45 s chunks.
- ScreenCaptureKit audio needs the Screen Recording grant even without video; already granted for the recorder.
