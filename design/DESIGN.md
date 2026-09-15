# Deskpouch design spec

Direction: "Mint ground, amber accent". Custom chrome, no native Settings window. One floating panel is the whole app. Mocks: `design/mocks/Final*.dc.html`, canvas page "Final".

## Tokens

Ground (mint-tinted near-black):

| token | value | use |
|---|---|---|
| bg | `#0d1211` | desktop fallback, ink on light elements |
| panel top | `#1a2320` | panel gradient start |
| panel bottom | `#121a17` | panel gradient end |
| card | `#161f1b` | tool cards, option cards |
| well | `#0d1411` | meter well inside the voice card |
| tint | `rgb(180,255,220)` | every hairline, border and subtle fill, at 0.03 to 0.18 alpha |

Text (cream, cool):

| token | value |
|---|---|
| text | `#e8f5ef` |
| text secondary | text at 0.62 alpha |
| text tertiary | text at 0.58 alpha |
| text faint | text at 0.55 alpha |

Accent (amber):

| token | value | use |
|---|---|---|
| accent | `#f59e0b` | meters, toggles on, region border, chip text base |
| accent high | `#fbbf24` | chip text, gradient top of the voice icon, pill meter |
| accent low | `#d97706` | gradient bottom of the voice icon, Region segment |
| accent ink | `#1c1917` | text or icon drawn on an amber fill |
| accent rgb | `245,158,11` | for alpha fills: 0.16 chip fill, 0.30 card border, 0.06 outer glow, 0.35 icon shadow |

Status:

| token | value |
|---|---|
| ok | `#2dd4a3` (mint) |
| record | `#fb7185` |

Font: Geist (400, 500, 600). Fallback SF Pro. No serif, no mono.

Type scale: 15/600 titles and tool names, 13/400 body, 13/500 transcript lines, 12 secondary, 11 meta and section labels (600, uppercase, 0.06em tracking), 10 keycap captions.

Radii: panel 18, card 14, recent row 12, meter well 10, icon tile 10, keycap 8, controls 7, chips and pills 999.

Shadows: panel `0 30px 70px rgba(0,0,0,0.65), 0 8px 20px rgba(0,0,0,0.4)` plus `inset 0 1px 0 rgba(255,255,255,0.06)`. Pill `0 20px 50px rgba(0,0,0,0.6)` plus a 6px outer ring in the state colour at 0.07 alpha.

## Components

- **Panel**: 400 wide, 18 padding, 16 gap. Drops from the menubar icon. Sections: header, Tools list (one row per tool), Recent, footer. A tool row opens the tool's view (back chevron, card, options); General is the same kind of pushed view.
- **Tool row**: 52 tall, radius 12, tint fill 0.03, border 0.07; tile 36, name 13/500, status 11 tertiary, shortcut keycaps 28, chevron. Listening: amber border 0.30 plus wash; recording: the same in record colour.
- **Header**: wordmark 15/600 left, status dot (ok, 6px, glow) plus "Ready" right. General view swaps the wordmark for a back chevron plus "General".
- **Tool card**: icon tile 36, name 15/600, one-line description 12 secondary, shortcut as keycaps on the right. Active card gets amber border at 0.30, amber wash gradient, 4px outer ring at 0.06. Voice card also has the 44px meter well.
- **Keycap**: 28 or 34 tall, tint gradient, tint border 0.18, `0 3px 0 bg` bottom shadow plus 1px inner highlight.
- **Chip**: 26 tall, pill. On: amber fill 0.16, border 0.40, text accent high, check icon. Off: tint fill 0.04, border 0.12, text secondary.
- **Options disclosure**: "Options" plus chevron on the chip row. Expanded: hairline, then 40px rows label left, control right. Chevron rotates 180.
- **Row controls**: popup (26 tall, tint fill 0.06, border 0.14, chevron), toggle (28x17, amber when on, knob accent ink), button (same as popup, no chevron).
- **Recent row**: 44x30 tile left (mic tile: amber 0.14 fill, 0.25 border, amber-high icon; recording: thumbnail with duration badge), title 13/500 truncated, meta 11 faint, 28px action button right.
- **History view**: pushed view; header with back tile, "History", count and size right. Full-width search well (32 tall, magnifier, plain field), then a segmented All / Voice / Recordings on its own line, left-aligned (32 well, 24 pills, selected pill in the chip's amber). Day sections labelled like section headers (Today, Yesterday, "Tue 8 Sep"); rows as Recent rows with clock times; hover lifts the row (tint 0.06 / border 0.12) and shows a record-coloured trash action. "Show older · N more" centred, 12 secondary.
- **Meter**: vertical bars 3 wide, 3 or 4 gap, fully rounded, amber. Panel 20 bars, pill 25 bars, menubar 7 bars at 2 wide.
- **Pill**: 52 tall, top-center just under the menubar by default (moved from bottom-center on 2026-09-15: chat inputs and terminals live at the bottom); General has a Pill position option, Top or Bottom. Non-activating. States: listening (amber ring, pulsing dot, meter, timer), transcribing (amber ring, sweeping hairline, "Transcribing", engine name; stays a pill, no transcript preview: decided 2026-09-15), pasted (mint ring, mint check disc, "Pasted into X", undo hint), recording (record ring, pulsing dot, timer, dims, Stop button in text colour with bg ink).
- **Brand assets** (`Packages/DeskpouchCore/Resources/Brand`, from the 2026-09-15 asset pack): the app icon (`App/Resources/AppIcon.icns`, built with iconutil from the 16 to 1024 px set; the asset catalog route dropped sizes), and the amber pouch mark used at 22 pt before the wordmark in the panel header. The wordmark stays typeset in Geist. The pack's outline menubar glyph was too fine at 18 pt and is not used.
- **Menubar icon**: idle glyph drawn in code (`MenubarGlyph.pouchOutline`: the brand's drawstring pouch as a 1.8 pt outline with beads and three meter bars, template; `pouch` is the solid variant; the snapshot test dumps both into menubar strips); listening amber pill with a 7-bar meter; recording pink pill with bg-ink dot and timer (ink, not white, for contrast).
- **Region picker**: dim `rgba(4,8,6,0.62)`, selection amber 2px border with 4px ring and glow, cream corner brackets, amber dimension chip, bottom pill toolbar with segmented Region/Window/Screen, round audio toggles, cream Record button with return hint.

## Motion

- Panel: spring in from the menubar icon, 220ms, slight scale from 0.96 anchored at the top; 120ms fade out. Done.
- Card expand: height animates, chevron rotates, 180ms ease-out. With milestone 5.
- Pill: states cross-fade in place, 200ms. Pasted auto-dismisses after 1.2s; saved after 2s. Recording pill dims to 0.55 after 4s, hover restores. Done.
- Meter bars: driven by live audio level, 30fps, with 80ms decay. Done.
