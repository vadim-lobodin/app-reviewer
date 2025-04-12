import Foundation
import Speech
import AVFoundation

class TranscriptionService {
    enum TranscriptionError: Error {
        case notAuthorized
        case noAudioFile
        case recognitionFailed(Error)
        case audioEngineFailed(Error)
    }
    
    private let audioURL: URL
    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var transcriptions: [Transcription] = []
    
    init(audioURL: URL) {
        self.audioURL = audioURL
    }
    
    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: true)
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func transcribeAudioFile() async throws -> [Transcription] {
        guard await requestAuthorization() else {
            throw TranscriptionError.notAuthorized
        }
        
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        
        // Configure request
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer?.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                    return
                }
                
                if let result = result, result.isFinal {
                    // Process transcription segments
                    let segments = result.bestTranscription.segments
                    
                    let transcriptions = segments.map { segment in
                        Transcription(
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration,
                            text: segment.substring,
                            summary: nil
                        )
                    }
                    
                    // Merge nearby segments with similar timestamps
                    let mergedTranscriptions = self.mergeNearbySegments(transcriptions, maxGap: 1.0)
                    
                    continuation.resume(returning: mergedTranscriptions)
                }
            }
        }
    }
    
    // Merge transcription segments that are close in time
    private func mergeNearbySegments(_ segments: [Transcription], maxGap: TimeInterval) -> [Transcription] {
        guard !segments.isEmpty else { return [] }
        
        var result: [Transcription] = []
        var currentSegment = segments[0]
        
        for i in 1..<segments.count {
            let nextSegment = segments[i]
            
            // If time gap is small, merge them
            if nextSegment.startTime - currentSegment.endTime < maxGap {
                currentSegment = Transcription(
                    startTime: currentSegment.startTime,
                    endTime: nextSegment.endTime,
                    text: currentSegment.text + " " + nextSegment.text,
                    summary: nil
                )
            } else {
                // Save current segment and start a new one
                result.append(currentSegment)
                currentSegment = nextSegment
            }
        }
        
        // Add the last segment
        result.append(currentSegment)
        return result
    }
    
    // Generate simple summaries
    func generateSummaries(for transcriptions: [Transcription]) -> [Transcription] {
        return transcriptions.map { transcription in
            var updatedTranscription = transcription
            
            // Simple rule-based summarization (extract first sentence or truncate)
            if let firstSentence = transcription.text.split(separator: ".").first,
               !firstSentence.isEmpty {
                updatedTranscription.summary = String(firstSentence) + "."
            } else if transcription.text.count > 100 {
                let truncated = String(transcription.text.prefix(100))
                updatedTranscription.summary = truncated + "..."
            } else {
                updatedTranscription.summary = transcription.text
            }
            
            return updatedTranscription
        }
    }
}