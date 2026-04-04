# Murmur

A macOS menu bar DVR -- a "Backtrack" rewind buffer that continuously captures screen, audio, and metadata so you can rewind, search, and replay the last hour of your computing session.

## Architecture: 5-Level Mental Model

Murmur is built around a **DVR rewind buffer** architecture with five cooperating layers:

### Level 1 -- Capture

Continuous ingestion of raw signals from the Mac environment:

- **ScreenCaptureKit** frame capture at 2 fps (background) / 30 fps (review)
- **AVAudioEngine** microphone recording with AAC encoding
- **NSWorkspace + Accessibility API** for frontmost app and window title tracking

### Level 2 -- Ring Buffer (Bounded Storage)

All media flows into a **bounded circular buffer** on disk:

- Directory of numbered chunk files (`chunk_000.mp4`, `chunk_001.m4a`, ...)
- Configurable max chunks (default: 360 chunks x 10 sec = 1 hour)
- Oldest chunk is overwritten when full
- **Key invariant: size never exceeds configured budget K**
- Properties: `currentIndex`, `totalDuration`, `diskUsage`

### Level 3 -- Extraction & Indexing

Two async pipelines run behind the capture layer and never block it:

- **Vision OCR pipeline** -- `VNRecognizeTextRequest` extracts text from screen frames and stores results in a SQLite FTS5 table keyed by `(timestamp, chunk_id)`
- **Speech framework transcription** -- `SFSpeechRecognizer` (on-device) processes audio chunks and stores transcripts in the same FTS5 database

### Level 4 -- Search Index (SQLite + FTS5)

A single SQLite database in Application Support with:

| Table | Columns | Purpose |
|-------|---------|---------|
| `ocr_text` | timestamp, chunk_id, text | Screen text |
| `transcripts` | timestamp, chunk_id, text | Audio transcripts |
| `metadata` | timestamp, app_name, window_title, url | App context |
| `ocr_fts` | FTS5 virtual table | Full-text search on OCR |
| `transcripts_fts` | FTS5 virtual table | Full-text search on transcripts |

Triggers keep FTS tables in sync with content tables automatically.

### Level 5 -- Timeline UI

SwiftUI interface for retrieval:

- Horizontal scrollable timeline showing chunk thumbnails
- Search bar querying the FTS5 index across OCR + transcripts + metadata
- Click to preview any moment (video + audio + text overlay)
- Results ranked by timestamp with type indicators (screen/audio/app)

## Features

- **Menu bar interface** -- no dock icon, stays out of your way
- **DVR rewind buffer** -- continuously captures and overwrites oldest data
- **Screen capture** via ScreenCaptureKit with configurable frame rate
- **Continuous audio recording** with automatic segment splitting
- **OCR text extraction** from screen frames (Vision framework)
- **On-device speech transcription** (Speech framework)
- **Full-text search** across all captured text (SQLite FTS5)
- **Active app/window tracking** with Accessibility API
- **Configurable disk budget** (100 MB - 5 GB) with automatic eviction
- **Buffer duration slider** (5 - 60 min)
- **Timeline UI** with search and preview
- **M4A (AAC) output** for compact, high-quality audio
- **Input device picker** -- choose any connected microphone
- **Launch at login** via SMAppService

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+
- Screen Recording permission (for ScreenCaptureKit)
- Microphone permission (for audio capture)
- Speech Recognition permission (for transcription)
- Accessibility permission (for window title tracking, optional)

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
Sources/
  CSQLite/                   -- System library module for SQLite3
    module.modulemap
    shim.h
  Murmur/
    MurmurApp.swift          -- @main SwiftUI app, wires all engines together
    AudioEngine.swift        -- AVAudioEngine capture, file writing, segment rotation
    ScreenCapture.swift      -- ScreenCaptureKit frame capture + delegate
    RingBuffer.swift         -- Bounded circular buffer (size <= K invariant)
    OCREngine.swift          -- Vision framework OCR pipeline -> FTS5
    TranscriptionEngine.swift -- Speech framework transcription -> FTS5
    SearchStore.swift        -- SQLite + FTS5 search index
    MetadataCapture.swift    -- Active app/window tracking via NSWorkspace + AX
    TimelineView.swift       -- Timeline UI with search and preview
    StatusBarView.swift      -- Menu bar dropdown (transport, buffer info, search)
    SettingsView.swift       -- Settings (audio, screen, buffer, processing, system)
    Permissions.swift        -- Microphone permission helpers
    Info.plist               -- Bundle metadata, usage descriptions
```

## Privacy

All data stays on your Mac. No network calls. The ring buffer enforces a strict disk budget and automatically evicts old data. OCR and transcription run entirely on-device.

## License

MIT
