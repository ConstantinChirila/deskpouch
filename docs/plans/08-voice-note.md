# 08 Voice note (append to daily note)

Lives inside `ToolVoice` as a second `Tool` instance, tool id `voicenote`, row "Voice note", hold key Right Command. Depends on 00 (pipeline action `appendToFile`).

## Decisions
- Same engine, language and microphone as Voice (shared `VoiceTool` core, two thin `Tool` wrappers with different id, hold key and default output). The Voice view's engine/model rows are not duplicated; the Voice note view shows "Engine: follows Voice" as a link.
- Default output: `appendToFile` + history. No paste, no copy.
- New pipeline action `appendToFile` with `AppendTarget { pathTemplate: String; heading: String?; lineTemplate: String }`:
  - `pathTemplate` default `<vault>/Daily/{yyyy-MM-dd}.md` (folder picker for the vault, filename pattern editable). Tokens: `{yyyy-MM-dd}`, `{HH:mm}`, `{text}`.
  - `heading` default `## Voice notes`. Created at end of file when missing; lines appended under it (after the last non-empty line of that section).
  - `lineTemplate` default `- {HH:mm} {text}`.
  - File created with `# {yyyy-MM-dd}` when missing. Written atomically; iCloud handles sync.
- Pill: `.saved(name: "Today's note", copied: false)` reused with text "Added to note".

## Structure
```
DeskpouchCore/Output/AppendTarget.swift   template expansion + section insert, pure, tested
DeskpouchCore/Output/OutputEffects        appendToFile(text, target) throws -> URL
ToolVoice/VoiceNoteTool.swift             wrapper
```

## Tests
Template tokens; insert under existing heading; heading missing; file missing; trailing newline handling; unicode text.

## Panel
Row status: "Daily/2026-09-16.md". Tool view: chips Append / Copy / History, option rows Folder, Filename, Heading, Line, Hold key.
