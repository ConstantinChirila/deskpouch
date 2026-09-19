# 10 Gallery

Requested and grilled 2026-09-19. Package `DeskpouchGallery` (imports Core only). Not a tool: no row, no hotkey.
Replaces the in-panel History view. Depends on 00 (history kinds, thumbnails) and 05 (the player).

## Goal
Look at, find, copy, drag out and delete what Deskpouch captured (screenshots, recordings, GIFs, transcripts,
colours) inside Deskpouch, with no trip to Finder, Preview or QuickTime.

## Decisions
- **One window, master-detail.** Left: a ~260 pt column of every history row, grouped by day, tiles with a real
  thumbnail (about 96x64), title and meta. Right: a large preview of the selected item. Selection is preview;
  nothing to open or close. Single instance, custom chrome like the editors, min 900x560, frame remembered,
  title "Gallery". Empty state says what to press to capture something.
- **Replaces the panel's History view.** The panel keeps Recent. "All" opens the gallery (or brings it forward).
  Each Recent row gains a hover preview button that opens the gallery with that item selected; a row's click stays
  copy. Show in Finder moves to the row's context menu. New captures appear live at the top of the column without
  taking the selection.
- **Contents: history rows only.** No folder scanning. A tool with its History chip off does not show up; that
  chip's help text says so.
- **Preview per kind**
  - Screenshot: fit to the pane on the well; click or Space toggles fit and 100%, scroll / pinch zooms, drag pans.
    Footer: pixel size, file size, folder.
  - Recording (mp4): the `AVPlayerLayer` player from Trim, with sound, scrub bar and time. No handles.
  - GIF: animated, looping, click pauses.
  - Text: readable column (max ~640 pt, 15 pt type), selectable. Footer: word count, pasted into X.
  - Colour: big swatch and the five formats, one copyable line each.
  - Missing file: cached thumbnail small, "File moved or deleted", Delete only.
- **Action bar** under the preview: Copy, Show in Finder, Annotate / Trim (opens the editor window), Star, Delete.
- **Keys**: ↑↓ move, Shift+↑↓ and ⌘ / Shift click extend, Space play or zoom, F and double-click fill the window with
  the preview (Esc back), Return Annotate / Trim, S star, ⌘C copy, ⌘⌫ delete, ⌘F search, ⌘A all.
- **Delete = row + file to the Trash** (`FileManager.trashItem`), never a hard delete, and only the row's own file
  (an original is untouched when its annotated or trimmed copy goes). Text and colour rows lose the row only. The
  thumbnail goes too. No prompt for up to 5 items; above that one confirm ("Move 12 items to the Trash?"). After a
  delete the selection moves to the next item. General's "Clear history" is unchanged: rows only, never files.
- **Missing files** stay visible, dimmed with a badge. When there are any, the filter bar shows "N missing · Clean
  up", which removes those rows after one confirm. Never pruned automatically: a save folder can be unreachable for
  a while (iCloud, external disk). Existence is checked off the main thread as each page loads.
- **Finding things**: search (transcript text, file names, colour values), kind chips with counts (All, Screenshots,
  Recordings, Text, Colours; GIFs count as recordings), date presets (Any time, Today, Last 7 days, Last 30 days,
  This year), a pasted-into / tool filter, a Starred chip. Day groups, pages of 50, newest first, no sort options.
  No tags, no custom date range (both considered and dropped 2026-09-19).
- **Starred**: a `starred` column, a star on the tile, S toggles it on the selection.
- **Thumbnails for recordings and GIFs**: a poster frame (about 10% in, at most 1 s) is stored through
  `HistoryThumbnails` when the result is delivered; rows from before get theirs the first time the gallery shows
  them. Recent in the panel gets them too.
- **Drag out**: a tile or the preview drags to any app as the file (every selected file with a multi-selection),
  text rows as plain text, colours as their value. Always a copy, never a move. ⌘C with several items copies all
  their files, or the texts joined by blank lines when all are text; a mixed selection copies the files.
- **Regular app while a real window is open.** Deskpouch is an accessory app (no Dock icon, no ⌘Tab). While the
  gallery or any editor (Annotate, Trim) is open it switches to `.regular`, and back to `.accessory` when the last
  one closes. That needs a proper main menu: App (About, Quit), Edit (Copy, Select All, Delete), Window (Close,
  Minimize). Step 0 (done 2026-09-19, on the editors): `EditorWindowController.onOpenChange` feeds the shell's
  `WindowPresence`, which flips the policy. Checked through `DESKPOUCH_DEMO=annotate-pill` and `annotate`: with an
  editor open `lsappinfo` reports Foreground, Deskpouch is frontmost and the menu bar shows Deskpouch, Edit, Window
  at once (the policy flips just before the window activates the app, so the reported hidden-menu quirk does not
  show); after the last editor closes it is UIElement again and the previous app has focus. Not checked by hand:
  ⌘Tab, the Dock icon coming and going, the menu items themselves.

## Structure
```
Packages/DeskpouchGallery/
  GalleryModel.swift        pure: items, selection (single, ⌘, Shift ranges), filters, paging, what is selected
                            after a delete, live inserts that keep the selection. Tested.
  GalleryFilter.swift       kind, date preset, starred, pasted-into, query -> store request. Tested.
  GalleryWindowController.swift
  GalleryView.swift         column + preview split
  Column/                   tiles, day headers, filter bar
  Preview/                  ImagePreview, VideoPreview, GIFPreview, TextPreview, ColorPreview, MissingPreview
Core:
  HistoryStore              filters (kind, date range, starred, pasted into), per-kind counts, `starred` column
                            (migration like `meta`), delete returning the file to trash
  HistoryThumbnails         poster frames for videos and GIFs
  WindowPresence (shell)    counts real windows, flips the activation policy
```
The Trim player view moves from `ToolScreenRecorder` to Core (or Capture) so the gallery can use it without
importing a tool. The app wires the gallery up: the store, and closures for copy, Annotate, Trim and reveal.

## Steps
0. Spike: activation policy switch + main menu, on the existing editors. **Done: regular-while-open it is.**
1. Core: store filters, counts, `starred`, trash-aware delete. Tests. **Done 2026-09-19**: `HistoryQuery` (text, tool, kinds, from / before, starred, pasted into), `items(_:)`, `count(_:)`, `countsByKind` (ignores the kind filter so each chip says what it would show), `pastedIntoApps`, `setStarred`, `setThumbnail`, `delete(ids:)` handing back the files; `starred` column with migration. Moving those files to the Trash is the caller's job and lands with step 2.
2. Window, column, selection, image and text preview, delete with multi-select. `GalleryModel` tests.
3. Video, GIF and colour preview; poster thumbnails with lazy backfill; missing-file state and Clean up.
4. Panel: "All" opens the gallery, the History view is removed, Recent rows get the preview button.
5. Starred, date presets, pasted-into filter.
6. Drag out, multi-copy.
7. `DESKPOUCH_DEMO=gallery` and verification.

## Tests
GalleryModel: Shift range from an anchor, ⌘ toggle, select-all within a filter, selection after deleting one / many /
the last item, a live insert keeps the selection, a filter change drops selected items that no longer match.
GalleryFilter: each date preset's bounds with an injected clock and time zone; GIFs counted as recordings.
HistoryStore: each new filter alone and combined, counts per kind, `starred` migration on an old database, delete
returns the file path. Posters: a synthetic 2 s video yields a thumbnail; a missing file yields none and no crash.

## Verify
`DESKPOUCH_DEMO=gallery`: opens on a database with every kind, steps through them (PNG per kind), stars one,
filters to Starred, deletes a throwaway screenshot and checks the file is in the Trash and the original of an
annotated copy is still there. By hand: drags into another app, ⌘Tab while open, Dock icon gone after closing.
