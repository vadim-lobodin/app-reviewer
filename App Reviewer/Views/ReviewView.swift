import SwiftUI
import AVKit

struct ReviewView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let session: RecordingSession
    
    @State private var selectedScreenshotIndex: Int = 0
    @State private var isPlayingVideo = false
    
    var body: some View {
        if session.screenshots.isEmpty {
            EmptyReviewView(session: session)
        } else {
            HStack(spacing: 0) {
                screenshotTimelineView
                    .frame(width: 200)
                    .background(Color(.windowBackgroundColor))
                
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var screenshotTimelineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(session.screenshots.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { index, screenshot in
                    thumbnailView(for: screenshot, at: index)
                        .onTapGesture {
                            selectedScreenshotIndex = index
                        }
                }
            }
            .padding()
        }
    }
    
    private func thumbnailView(for screenshot: Screenshot, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let thumbnailURL = screenshot.thumbnailURL, 
               let thumbnailImage = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 90)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(selectedScreenshotIndex == index ? Color.blue : Color.clear, lineWidth: 3)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 160, height: 90)
                    .cornerRadius(4)
            }
            
            Text(screenshot.formattedTimestamp)
                .font(.caption)
                .foregroundColor(selectedScreenshotIndex == index ? .primary : .secondary)
        }
    }
    
    private var detailView: some View {
        VStack(spacing: 0) {
            if session.screenshots.indices.contains(selectedScreenshotIndex) {
                let screenshot = session.screenshots.sorted(by: { $0.timestamp < $1.timestamp })[selectedScreenshotIndex]
                
                ScreenshotDetailView(
                    screenshot: screenshot,
                    transcriptions: relatedTranscriptions(for: screenshot),
                    onPlayVideo: {
                        playVideo(at: screenshot.timestamp)
                    }
                )
            } else {
                Text("Select a screenshot to view details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func relatedTranscriptions(for screenshot: Screenshot) -> [Transcription] {
        return session.transcriptions.filter { transcription in
            // Find transcriptions that overlap with this screenshot's timestamp
            let buffer: TimeInterval = 2.5 // Consider transcriptions within 2.5 seconds
            return (transcription.startTime - buffer...transcription.endTime + buffer).contains(screenshot.timestamp)
        }.sorted(by: { $0.startTime < $1.startTime })
    }
    
    private func playVideo(at timestamp: TimeInterval) {
        guard let videoURL = session.videoURL else { return }
        
        // Create and configure player
        let player = AVPlayer(url: videoURL)
        let seconds = CMTime(seconds: timestamp, preferredTimescale: 600)
        player.seek(to: seconds)
        player.play()
        
        // Show in player window (macOS specific approach)
        let hostingController = NSHostingController(rootView: PlayerView(player: player))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingController.view
        window.title = "Video Playback"
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

struct ScreenshotDetailView: View {
    let screenshot: Screenshot
    let transcriptions: [Transcription]
    let onPlayVideo: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Screenshot at \(screenshot.formattedTimestamp)")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: onPlayVideo) {
                        Label("Play Video", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                // Fixed: Don't use optional binding for non-optional imageURL
                if let image = NSImage(contentsOf: screenshot.imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                if !transcriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Commentary")
                            .font(.headline)
                        
                        ForEach(transcriptions) { transcription in
                            TranscriptionItemView(transcription: transcription)
                        }
                    }
                    .padding()
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .padding(.horizontal)
                } else {
                    Text("No commentary found for this moment")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.vertical)
        }
    }
}

struct TranscriptionItemView: View {
    let transcription: Transcription
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transcription.formattedTimeRange)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let summary = transcription.summary {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(transcription.text)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.bottom, 5)
            
            Divider()
        }
        .padding(.vertical, 5)
    }
}

struct EmptyReviewView: View {
    let session: RecordingSession
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var isAnalyzing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No review data available")
                .font(.title2)
            
            // This check is correct since videoURL and audioURL are optional
            if session.videoURL != nil && session.audioURL != nil {
                Button("Generate Analysis") {
                    isAnalyzing = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("This session does not have complete recording data")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isAnalyzing) {
            AnalysisView(session: session)
                .environmentObject(sessionManager)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

#Preview {
    ReviewView(session: RecordingSession())
        .environmentObject(SessionManager())
}