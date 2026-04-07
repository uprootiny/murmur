# Murmur Handoff (Codex -> Claude Code)

## Scope
Canonical app root: `/home/uprootiny/fie/murmur`
Ignore: `/tmp/murmur-repo`, `public/index.html`

## M1 Goal (Alive Loop)
Mic capture -> chunk files -> ring buffer -> timeline UI -> scrub.

## What was done (no local Swift toolchain available)
- Fixed ring buffer ordering to use ring index and expose `chunkCount` + `chunkDurationSeconds`.
- Timeline duration derives from ring buffer count.
- UI refresh timer set to 200ms.
- Fake playback (play/pause advances playhead without audio).
- CI workflow with build/lint/test and Xcode matrix.
- Removed an unused stored property to avoid warnings-as-errors in CI.

## Verification Checklist (run on macOS with Xcode/Swift)
1) Build
```bash
cd /home/uprootiny/fie/murmur
swift build -c release
```

Legacy (High Sierra) build:
```bash
swift build -c release -Xswiftc -DMURMUR_LEGACY
```

2) Tests
```bash
swift test
```

3) Run app
- Open `/home/uprootiny/fie/murmur/Package.swift` in Xcode
- Run `MurmurApp`

4) Validate M1 behavior
- Mic permission prompt appears
- Chunk files appear at:
  `~/Library/Application Support/Murmur/Audio/chunk_000.m4a`
- Timeline "Buffer" label increases over time
- Slider max increases over time
- Scrubbing moves playhead in bar
- Play button advances playhead (fake playback)
- Check log file for liveness:
  `~/Library/Application Support/Murmur/Logs/murmur.log`

## Known limitations
- No real playback yet
- No export re-encode
- Ring buffer metadata is derived from order/time, not persisted
- System audio, screen capture, OCR, transcription not implemented

## CI
Workflow: `murmur/.github/workflows/ci.yml`
- Build + lint + test on macOS 14
- Xcode 15.3 and 15.4 matrix
- SwiftPM cache for `.build` and `~/.swiftpm`

## If build errors occur
Check for:
- SwiftPM warnings-as-errors (lint job). Remove unused variables or unused results.
- AppKit/AVFoundation imports in `MurmurApp` targets.

## Files to inspect first
- `murmur/Sources/MurmurApp/main.swift`
- `murmur/Sources/MurmurApp/TimelineWindowController.swift`
- `murmur/Sources/MurmurCore/AudioCaptureService.swift`
- `murmur/Sources/MurmurCore/AudioChunkWriter.swift`
- `murmur/Sources/MurmurCore/RingBuffer.swift`
- `murmur/Sources/MurmurCore/TimelineModel.swift`
