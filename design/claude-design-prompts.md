# Claude Design prompts for Deskpouch

Paste the context block first in every new session, then one surface prompt at a time. The mocks in `design/mocks/Final*.dc.html` are the reference; export a PNG of the matching artboard and attach it with the prompt for best results.

## Context block (paste first, always)

```
Deskpouch is a native macOS 15 menubar app for personal capture tools. Two tools in v1: Voice (hold Right Option, speak, release, transcript is pasted into the active app, transcription is local via Parakeet) and Record screen (Cmd Shift 6 opens a region/window/screen picker, records to H.264 mp4, saves and copies the file). More tools will be added later, so every surface must scale to N tools without redesign.

There is no main window and no Settings window. One floating panel drops from the menubar icon and is the whole app. Tool cards expand in place for their options. A "General" view lives inside the same panel behind a back chevron.

Visual system, follow exactly:
- Ground: mint-tinted near-black. Background #0d1211. Panel gradient #1a2320 to #121a17. Cards #161f1b. Meter well #0d1411. Every hairline and subtle fill is rgb(180,255,220) at 0.03 to 0.18 alpha.
- Text: #e8f5ef. Secondary at 0.62 alpha, meta at 0.55 to 0.58.
- Accent: amber #f59e0b, high #fbbf24, low #d97706. Ink on amber is #1c1917. Alpha fills use rgb(245,158,11): chips 0.16, active card border 0.30, outer glow 0.06.
- Status: ok mint #2dd4a3, record #fb7185.
- Font: Geist only. 15/600 titles, 13 body, 13/500 transcripts, 12 secondary, 11 uppercase section labels with 0.06em tracking. No serif, no mono.
- Radii: panel 18, card 14, row 12, keycap 8, controls 7, chips and pills fully round.
- Shortcuts are drawn as physical keycaps: tint gradient, 1px tint border, a 3px solid bottom shadow in the background colour, 1px inner top highlight.
- Audio is shown as vertical bar meters (3px bars, fully rounded, amber), never curves.
- Icons are stroke-based, 16 to 18px. No emoji.
- Copy is terse. No marketing language.
```

## Surface 1: the panel

```
Design the Deskpouch panel, 400px wide, 18px padding, 16px gap between sections, dropping from the menubar icon.

Top to bottom:
1. Header: "Deskpouch" 15/600 left. Right: a 6px mint dot with glow and "Ready" in 11px faint text.
2. Voice card (active): amber 0.30 border, faint amber wash from top-left, 4px outer ring at 0.06. Row: 36px amber gradient icon tile with a mic, "Voice" 15/600 with "Hold to talk, release to paste" below in 12px secondary, and on the right a tiny uppercase "hold" caption next to a 42x34 keycap showing ⌥. Below: a 44px meter well with a 20-bar amber meter on the left and "Parakeet v3 · local" in 11px on the right. Below: chips Paste, Copy, History (on) and Notify (off), and "Options" with a chevron on the right.
3. Record screen card (inactive): tint border 0.10. Same row anatomy: dark icon tile with a camera glyph and a red dot, "Record screen", "Region, window or screen · 1080p · system audio", three 28px keycaps ⌘ ⇧ 6.
4. Recent: uppercase label with "48 items" right. Three rows, each a 44x30 tile, a 13/500 truncated title, 11px meta, and a 28px action button. Transcript rows use an amber-tinted mic tile and a copy action. Recording rows use a thumbnail with a duration badge and a reveal action.
5. Footer: gear icon plus "General" left, "Quit ⌘Q" right, 12px faint.

Then show the same panel with the Voice card's Options open: a hairline, then 40px rows for Model (popup "Parakeet TDT v3" with "600 MB · downloaded" beside it), Language (popup "Auto detect"), Microphone (popup), Shortcut (keycap plus "click to change"). The chevron is rotated.

Question to answer visually: with five tools, does the active card stay on top, or do cards keep a fixed order and the active one just lights up? Show both.
```

## Surface 2: General view

```
Design the General view of the Deskpouch panel. Same 400px panel. Header becomes a 24px back-chevron button plus "General"; the mint status dot stays on the right.

Three cards of 40px rows, label left and control right, a 2px sub-label in 11px faint under labels that need it:
Card 1: Launch at login (toggle on). Sounds, "Start and stop cues" (toggle on). Show timer in menubar, "While recording" (toggle on).
Card 2: Keep history, "48 items · 212 MB" (toggle on). Transcripts in history, "Off keeps only recordings" (toggle on). Clear history (button "Clear…").
Card 3: Permissions with a mint check and "Mic · Screen · Accessibility". Version "0.1.0" with a "Check for updates" button.

Toggles are 28x17, amber when on with a dark knob, tint 0.14 when off with a cream knob.
```

## Surface 3: the pill

```
Design the Deskpouch floating pill. 52px tall, fully rounded, bottom-center of the screen, panel gradient background, non-activating, disappears on its own. Four states stacked with a small uppercase label to the left of each:

1. Listening: amber border at 0.40 with a 6px outer ring at 0.07, a 12px pulsing amber dot with glow, a 25-bar amber-high meter, "0:04" in 12px tabular secondary.
2. Transcribing: the pill grows into a 440px card with 20px radius. Transcript typing in at 15/500 with an amber caret, then a row with a 40px progress hairline (amber on amber 0.20) and "Parakeet v3 · 0.2s" in 11px.
3. Pasted: mint border and ring, a 24px mint disc with a dark check, "Pasted into Slack" 14/500, a hairline divider, "⌘Z to undo" in 12px secondary.
4. Recording: record-pink border and ring, pulsing pink dot, "0:42" 15/500 tabular, "1040 × 760 · 60 fps" secondary, divider, and a 34px Stop button in cream with dark text and a small square.

Describe in words the morph between listening and transcribing.
```

## Surface 4: region picker

```
Design the full-screen region picker at 1440x900. The screen is dimmed with rgba(4,8,6,0.62) over two placeholder app windows. The selected region is undimmed with a 2px amber border, a 4px amber ring at 0.18 and a soft amber glow, plus four cream corner brackets (3px, 18px long) just outside the corners. Above the top-left corner sits a solid amber chip: "1040 × 760", a thin divider, "16:9 snap".

Bottom-center toolbar: 60px tall pill, panel gradient, tint border. Inside: a dark inset segmented control (Region selected as an amber gradient pill with dark text and a corner-bracket icon; Window and Screen as ghost segments), two 36px round toggles for system audio (on: amber 0.16 fill, 0.40 border) and mic (off: tint 0.04), a hairline divider, a cream Record button 42px tall with a red dot and a small "↩" key hint, then "esc" in faint text.

Question to answer visually: with more tools, do tool-specific picker options belong in this toolbar or in a popover from the toolbar? Show the toolbar with two extra options added both ways.
```

## Surface 5: menubar icon

```
Design the Deskpouch menubar icon in three states on a dark macOS menubar strip: idle (a small pouch glyph, stroke-based, in cream at 0.85), listening (a 20px amber-tinted pill containing a 7-bar amber meter at 2px bar width), recording (a 20px solid record-pink pill with a dark #0d1211 dot and a tabular "0:42" in the same dark ink). Show all three next to the system clock.
```
