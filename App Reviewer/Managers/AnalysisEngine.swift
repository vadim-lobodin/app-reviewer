import Foundation
import SwiftUI

class AnalysisEngine: ObservableObject {
    enum AnalysisState {
        case idle
        case analyzing
        case complete
        case error(String)
    }
    
    @Published var state: AnalysisState = .idle
    @Published var progress: Double = 0.0
    @Published var session: RecordingSession
    
    private let sessionManager: SessionManager
    
    init(session: RecordingSession, sessionManager: SessionManager) {
        self.session = session
        self.sessionManager = sessionManager
    }
    
    func analyzeSession() async {
        await MainActor.run {
            state = .analyzing
            progress = 0.1
        }
        
        guard let videoURL = session.videoURL,
              let audioURL = session.audioURL else {
            await MainActor.run {
                state = .error("Missing video or audio files")
            }
            return
        }
        
        let sessionDirectory = sessionManager.sessionDirectoryURL(for: session)
        let screenshotsDirectory = sessionDirectory.appendingPathComponent("screenshots")
        
        // Extract frames
        await MainActor.run {
            progress = 0.2
        }
        
        do {
            let frameExtractor = FrameExtractor(
                videoURL: videoURL,
                interval: 5.0, // Extract a frame every 5 seconds
                outputDirectory: screenshotsDirectory
            )
            
            let screenshots = try await frameExtractor.extractFrames()
            
            await MainActor.run {
                progress = 0.5
            }
            
            // Transcribe audio
            let transcriptionService = TranscriptionService(audioURL: audioURL)
            let transcriptions = try await transcriptionService.transcribeAudioFile()
            
            await MainActor.run {
                progress = 0.8
            }
            
            // Generate summaries
            let transcriptionsWithSummaries = transcriptionService.generateSummaries(for: transcriptions)
            
            // Fixed Swift 6 concurrency warnings by passing values directly instead of capturing mutable variable
            let finalScreenshots = screenshots
            let finalTranscriptions = transcriptionsWithSummaries
            
            // Save updated session
            await MainActor.run {
                // Create and update the session within the MainActor context
                var localSession = self.session
                localSession.screenshots = finalScreenshots
                localSession.transcriptions = finalTranscriptions
                
                self.session = localSession
                self.sessionManager.updateSession(localSession)
                self.progress = 1.0
                self.state = .complete
            }
            
        } catch {
            await MainActor.run {
                state = .error("Analysis failed: \(error.localizedDescription)")
            }
        }
    }
}