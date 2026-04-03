# Murmur

A lightweight macOS menu bar app for continuous background audio recording.

## Features

- **Menu bar interface** -- no dock icon, stays out of your way
- **Continuous recording** with automatic 30-minute segment splitting
- **M4A (AAC) output** for compact, high-quality recordings
- **Input device picker** -- choose any connected microphone
- **Configurable quality** -- 48 kHz (high) or 22 kHz (low)
- **Launch at login** via SMAppService
- **Recordings stored** in `~/Documents/Murmur/` by default

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+

## Build

```bash
# Debug build
swift build

# Release build + .app bundle
chmod +x build.sh
./build.sh

# Run the app
open build/Murmur.app
```

## Project Structure

```
Sources/Murmur/
  MurmurApp.swift      -- @main SwiftUI app entry point (MenuBarExtra)
  AudioEngine.swift     -- AVAudioEngine capture, file writing, segment rotation
  StatusBarView.swift   -- Menu bar dropdown UI (transport, device picker)
  SettingsView.swift    -- Settings window (quality, storage, launch at login)
  Permissions.swift     -- Microphone permission helpers
  Info.plist            -- Bundle metadata, LSUIElement, mic usage description
```

## License

MIT
