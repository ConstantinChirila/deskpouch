# 02 Text grab (OCR)

Package `ToolTextGrab`, tool id `textgrab`, row "Text grab", hotkey ⌘⇧8. Depends on 00 and reuses `StillCapture`.

## Decisions
- Own tool, own hotkey, region-only picker in text style (no window/screen modes; the toolbar hides the segment).
- Vision `RecognizeTextRequest` (Swift API, macOS 15) at `.accurate`, `usesLanguageCorrection = false` (code and identifiers must not get "corrected"). `recognitionLanguages` = voice language hint first, then automatic.
- Output text keeps line breaks: observations sorted by top-left y then x, one line per observation, whitespace trimmed, blank lines collapsed to one.
- Result is text: defaults paste + copy + history, same as Voice. Pill: "Transcribing" reuse → `.pasted(target:)` / `.copied`.
- Empty result: pill `.failed("No text found")`, nothing pasted, nothing logged.

## Structure
```
ToolTextGrab/
  TextGrabTool.swift       keyPressed → picker → StillCapture → recognise → emit
  TextLayout.swift         pure: [Observation(rect, string)] → String. Tested.
```

## Tests
`TextLayout`: ordering of two columns, collapsing blank lines, trimming, right-to-left not handled (documented).

## Verify
`DESKPOUCH_DEMO=textgrab` captures a fixed rect over a Terminal window showing a known string and asserts the pasteboard.

## Panel
Row status: "Lines · EN". Tool view: chips Paste / Copy / History, option rows Language (shares the Voice list), Shortcut.
