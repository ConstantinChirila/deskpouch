# 05 Recording trim + GIF

Lives inside `ToolScreenRecorder`. Depends on 00 (editor, pill button).

## Decisions
- After Stop, the `.saved` pill gains a **Trim** button for 6 s (same pattern as Annotate). Every recording row in Recent/History gets Trim on hover.
- Trim window (editor): `AVPlayerView`-free custom player (AVPlayer + `AVPlayerLayer` in an NSViewRepresentable), filmstrip of thumbnails from `AVAssetImageGenerator`, in/out handles, Space play/pause, I and O set handles at the playhead, arrows step one frame.
- Format chip: **MP4** (default) / **GIF**.
  - MP4: `AVAssetExportSession` with `AVAssetExportPresetPassthrough` and `timeRange`, output `Recording … trimmed.mp4` beside the original. No re-encode, seconds to finish.
  - GIF: `AVAssetReader` at 12 fps, scaled to max 960 px wide, frames written with `CGImageDestination` (UTType.gif, `kCGImagePropertyGIFDelayTime`, loop 0). ImageIO's own quantiser is 256 colours global per frame; acceptable for UI recordings. Above 15 s the bottom bar shows an amber "GIF over 15 s: N MB" warning; export still allowed.
  - Estimated size shown before export (GIF: frames × approx bytes from a 1 s probe).
- Export emits a new `ToolResult` (kind recording) through the pipeline: Save (already in place), Copy file, History. The original stays untouched.

## Structure
```
ToolScreenRecorder/Trim/
  TrimModel.swift       pure: duration, in/out, clamps, snapping to 0.1 s. Tested.
  TrimDocument.swift    EditorDocument
  TrimView.swift
  GIFExporter.swift     reader → destination, progress
  MP4Exporter.swift     passthrough export
```

## Tests
TrimModel: in < out, minimum 0.5 s, step by frame at 60 fps, handle drag past the other side swaps nothing.
GIFExporter: 1 s synthetic asset (generated with AVAssetWriter in the test) → GIF with 12 frames, width ≤ 960.

## Verify
`DESKPOUCH_DEMO=record` then Trim in the pill → cut 1 s each side → MP4 duration matches; GIF opens in Preview and animates.
