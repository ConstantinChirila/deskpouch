# 06 Demo polish for recordings

Lives inside `ToolScreenRecorder` plus overlays from `DeskpouchCapture`. Depends on 00 (`OverlayWindow`). Webcam bubble is v2 and not in this plan.

## Decisions
Three toggles in the recorder's options, all off by default, all persisted under `screen.*`:

1. **Click ripple** (`screen.clicks`). Global `NSEvent` monitor (Accessibility grant already required) for left/right mouse down. Draws a 44 pt amber ring that expands and fades over 400 ms at the click point on an `OverlayWindow`. Right click uses record colour.
2. **Keystrokes** (`screen.keys`). Global keyDown monitor. Shows a keycap chip (DESIGN.md keycap style, 34 tall) bottom-centre of the recorded display: modifiers + key, e.g. ⌘⇧P. Plain typing shows the last 12 characters in one chip; modifier combos get their own chip. Hidden 1.2 s after the last key. Password fields: `NSSecureTextField` cannot be detected from a global monitor, so the chip shows "•••" whenever the frontmost app reports a secure input session (`IsSecureEventInputEnabled()`).
3. **Presenter mode** (`screen.presenter`). On start: hide desktop icons, turn on a Focus. On stop or crash-restart: restore.
   - Desktop icons: `defaults write com.apple.WindowManager StandardHideDesktopIcons -bool true` (Sonoma+ setting behind Desktop & Dock › Show Items › On Desktop). Unverified whether Finder picks it up live without a restart; if not, fall back to `com.apple.finder CreateDesktop false` + `killall Finder` and note it in the option's description.
   - Focus: there is no public API. Run `shortcuts run "Deskpouch Presenting"` and `… "Deskpouch Done"`, two shortcuts the user creates once (Set Focus on/off). The option row shows "Shortcuts missing" when `shortcuts list` lacks them.
   - Previous state stored in `screen.presenter.restore` so an unclean quit restores on next launch.

## Exclusion change
Today the whole app is excluded from display captures. Overlays must be in the file, so the filter becomes `SCContentFilter(display:excludingWindows:)` with the pill, panel and picker windows listed. Capture tools register their windows with `OverlayController.excludedWindows`. Window mode (`desktopIndependentWindow`) cannot show overlays; Click ripple and Keystrokes are disabled in the picker when Window is selected, with a hint.

## Structure
```
DeskpouchCapture/Overlays/  OverlayWindow (00), RippleView, KeycapChipView
ToolScreenRecorder/Polish/  ClickMonitor, KeyMonitor, PresenterMode (state machine, tested with a fake runner)
```

## Tests
KeyMonitor formatting (⌘⇧P, typed run coalescing, secure input placeholder). PresenterMode: start/stop/restore ordering with a recorded fake shell runner.

## Verify
Record a 5 s region with all three on: file shows ripple and chip, desktop icons gone during recording and back after Stop.
