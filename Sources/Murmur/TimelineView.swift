import AVKit
import SwiftUI

/// Timeline retrieval UI: a horizontal scrollable view of buffered chunks
/// with search, thumbnails, and preview playback.
struct TimelineView: View {
    @ObservedObject var ringBuffer: RingBuffer
    @ObservedObject var searchStore: SearchStoreObservable
    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedChunkURL: URL?
    @State private var selectedTimestamp: Date?
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding()

            Divider()

            if isSearching && !searchResults.isEmpty {
                // Search results list
                searchResultsList
            } else {
                // Timeline strip
                timelineStrip
            }

            Divider()

            // Preview panel
            previewPanel
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search recordings...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                    isSearching = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Search") {
                performSearch()
            }
            .disabled(searchQuery.isEmpty)
        }
    }

    // MARK: - Timeline Strip

    private var timelineStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Text(ringBuffer.formattedDuration + " buffered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 2) {
                    let chunks = ringBuffer.orderedChunks()
                    ForEach(Array(chunks.enumerated()), id: \.offset) { index, url in
                        chunkThumbnail(url: url, index: index)
                            .onTapGesture {
                                selectedChunkURL = url
                                selectedTimestamp = chunkTimestamp(index: index)
                            }
                    }

                    if chunks.isEmpty {
                        Text("No chunks buffered yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 100)
        }
    }

    // MARK: - Chunk Thumbnail

    private func chunkThumbnail(url: URL, index: Int) -> some View {
        ZStack {
            // Placeholder thumbnail
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 60)

            // Chunk number overlay
            VStack {
                Spacer()
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(2)
            }
            .frame(width: 80, height: 60)

            // Selection highlight
            if selectedChunkURL == url {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 80, height: 60)
            }
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        List(searchResults) { result in
            searchResultRow(result)
                .onTapGesture {
                    selectSearchResult(result)
                }
        }
        .frame(maxHeight: 200)
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                resultTypeIcon(result.type)
                Text(result.snippet)
                    .lineLimit(2)
                    .font(.body)
                Spacer()
                Text(formatTimestamp(result.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func resultTypeIcon(_ type: SearchResult.ResultType) -> some View {
        Group {
            switch type {
            case .ocr:
                Image(systemName: "doc.text.viewfinder")
                    .foregroundColor(.blue)
            case .transcript:
                Image(systemName: "waveform")
                    .foregroundColor(.green)
            case .metadata:
                Image(systemName: "app.badge")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack {
            if let url = selectedChunkURL {
                HStack(alignment: .top, spacing: 16) {
                    // Video / audio player
                    VideoPlayerView(url: url)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .cornerRadius(8)

                    // Metadata sidebar
                    if let ts = selectedTimestamp {
                        metadataSidebar(timestamp: ts)
                            .frame(width: 200)
                    }
                }
                .padding()
            } else {
                Text("Select a chunk or search result to preview")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 200)
            }
        }
    }

    private func metadataSidebar(timestamp: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            LabeledContent("Time", value: formatTimestamp(timestamp))

            if ringBuffer.diskUsage > 0 {
                LabeledContent("Disk", value: ringBuffer.formattedDiskUsage)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        searchResults = searchStore.store.search(query: searchQuery)
    }

    private func selectSearchResult(_ result: SearchResult) {
        let slot = result.chunkID % ringBuffer.maxChunks
        if let url = ringBuffer.chunkURL(at: slot, extension: "mp4") ??
                      ringBuffer.chunkURL(at: slot, extension: "m4a") {
            selectedChunkURL = url
            selectedTimestamp = result.timestamp
        }
    }

    private func chunkTimestamp(index: Int) -> Date {
        // Approximate timestamp based on chunk index and duration
        let secondsAgo = Double(ringBuffer.chunkCount - index) * ringBuffer.chunkDurationSeconds
        return Date().addingTimeInterval(-secondsAgo)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Video Player Wrapper

struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player?.currentItem?.asset != AVURLAsset(url: url) {
            nsView.player = AVPlayer(url: url)
        }
    }
}

// MARK: - Observable Wrapper for SearchStore

/// Thin ObservableObject wrapper so SearchStore can be used with @ObservedObject.
final class SearchStoreObservable: ObservableObject {
    let store: SearchStore

    init(store: SearchStore) {
        self.store = store
    }
}
