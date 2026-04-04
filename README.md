# Murmur

Murmur is a macOS menu bar app that provides a rolling audio rewind buffer with a timeline UI for quick recall.

## MVP scope (Sequoia floor)
- Menu bar only app
- Continuous audio capture (mic and optional system audio)
- Ring buffer storage with bounded disk usage
- Timeline UI for scroll back, preview, and save
- Export clips

## Architecture notes
See Docs/ARCHITECTURE.md

## Build (draft)
This is a Swift Package scaffold meant to be opened in Xcode.

- Open `murmur/Package.swift` in Xcode
- Build the `MurmurApp` target

### Legacy build toggle (High Sierra)
To force legacy fallbacks (no modern permission prompt path), build with:

```bash
swift build -c release -Xswiftc -DMURMUR_LEGACY
```

## Fallback plan
An El Capitan branch should replace ScreenCaptureKit and modern APIs with legacy equivalents.
Details are in Docs/ARCHITECTURE.md
