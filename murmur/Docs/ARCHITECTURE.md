# Murmur Architecture

This document describes the target architecture for a menu bar app that records a rolling audio buffer and provides a timeline UI for recall.

## Goals
- Continuous audio capture in background
- Bounded ring buffer storage with strict disk cap
- Timeline UI with instant scrub and save
- Privacy by default: buffer overwrites unless user saves
- Sequoia (macOS 15) as MVP floor
- El Capitan (macOS 10.11) fallback branch using legacy APIs

## System axioms
1) Ring buffer is the source of truth
2) Chunks are atomic and replaceable
3) Time is derived from chunk order (for now)
4) Capture must never block
5) UI reads state; it never writes core state

## High level pipeline
1) Capture
   - Microphone input
   - Optional system audio input
2) Encode
   - Low latency AAC encode for storage
3) Buffer
   - Ring buffer of fixed total disk usage
4) Index
   - Lightweight time index and bookmarks
5) Retrieve
   - Timeline UI for scrub, preview, and export

## Modules
- MurmurApp
  - Menu bar UI
  - Timeline window
  - App lifecycle and permissions
- MurmurCore
  - Capture pipeline
  - Ring buffer storage
  - Timeline model
  - Export and clip management

## Data model (core)
- Chunk
  - id: UUID
  - startTime: Date
  - duration: TimeInterval
  - url: URL
  - sizeBytes: UInt64
- BufferIndex
  - totalDuration: TimeInterval
  - chunks: [Chunk] ordered oldest to newest
  - currentWriteIndex: Int
- Bookmark
  - id: UUID
  - timestamp: Date
  - note: String

## Ring buffer design
- Fixed number of chunk slots and a fixed disk budget.
- Each chunk is a short AAC file (e.g. 10-30 seconds).
- When the buffer is full, the oldest chunk is overwritten.
- Invariant: total size <= maxDiskBytes.
 - Chunks are append-only once written; replacement happens at slot overwrite.

## Timeline UI
- Timeline is a projection over chunk order (source of truth is buffer).
- UI is a lens: reads from core state and issues intents, does not mutate buffer state directly.

## Concurrency model
- Capture pipeline uses a dedicated serial queue.
- Encode and disk writes stay off the main thread.
- UI reads from a thread safe snapshot of BufferIndex.
- Capture must never block; dropped frames are preferable to backpressure.

## macOS Sequoia MVP APIs
- Audio capture
  - AVAudioEngine inputNode tap
  - System audio via ScreenCaptureKit audio stream
- Encoding
  - AVAudioConverter to AAC
- Menu bar
  - NSStatusBar + NSStatusItem
  - SwiftUI for timeline window

## El Capitan fallback branch
The fallback branch should replace modern APIs with older equivalents.

- Audio capture
  - AVAudioEngine is available on 10.11
  - System audio capture likely requires a virtual driver (Loopback or BlackHole)
  - Provide configuration to select the system audio device if present
- Encoding
  - AudioConverter or ExtAudioFile for AAC
- UI
  - AppKit NSView-based timeline (SwiftUI is not available)
- Permissions
  - Microphone usage description via Info.plist

## High Sierra build toggle
Use `-DMURMUR_LEGACY` to force legacy API fallbacks on macOS 10.13 builds.

## Testing approach
- Unit tests for ring buffer index math
- Integration tests for chunk creation and cleanup
- Manual QA for timeline scrub and export

## Next steps
- Implement RingBuffer with disk budget enforcement
- Implement AudioCaptureService
- Implement TimelineModel and UI
- Replace export placeholder with audio concatenation and re-encode pipeline
