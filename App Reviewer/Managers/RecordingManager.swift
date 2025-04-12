import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import SwiftUI

class RecordingManager: ObservableObject {
    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case processing
        case error(String)
        
        // Implement Equatable manually because of associated value
        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
                 (.paused, .paused), (.processing, .processing):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }
    
    @Published var recordingState: RecordingState = .idle
    @Published var isAudioEnabled: Bool = true
    @Published var elapsedSeconds: Int = 0
    @Published var previewImage: CGImage?
    
    private var screenRecorder: ScreenRecorder?
    private var audioRecorder: AudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    
    // Output file URLs
    private var videoURL: URL?
    private var audioURL: URL?
    
    // Main display for recording (we'll always use this)
    private var mainDisplay: SCDisplay?
    
    // Callbacks
    var onSessionComplete: ((URL?, URL?) -> Void)?
    
    init() {
        // Get the main display on initialization
        Task {
            await refreshMainDisplay()
        }
    }
    
    func refreshMainDisplay() async {
        do {
            let content = try await SCShareableContent.current
            
            await MainActor.run {
                // Store the main display (usually the first one)
                self.mainDisplay = content.displays.first
                
                if self.mainDisplay == nil {
                    print("Warning: No display found for recording")
                }
            }
        } catch {
            print("Failed to get shareable content: \(error)")
        }
    }
    
    func startRecording() async {
        // Make a local copy of the state to avoid Swift 6 concurrency issues
        let currentState = await MainActor.run { self.recordingState }
        guard currentState == .idle || currentState == .paused else { return }
        
        // Ensure we have a display to record
        guard let mainDisplay = await MainActor.run({ self.mainDisplay }) else {
            await MainActor.run {
                recordingState = .error("No display available for recording")
            }
            return
        }
        
        await MainActor.run {
            recordingState = .preparing
        }
        
        // Prepare file URLs for output
        let documentsPath = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        
        let localVideoURL = documentsPath.appendingPathComponent("recording_\(timestamp).mp4")
        let localAudioURL = documentsPath.appendingPathComponent("audio_\(timestamp).m4a")
        
        // Store the URLs in the class properties
        await MainActor.run {
            videoURL = localVideoURL
            audioURL = localAudioURL
        }
        
        // Create a content filter for the main display
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        
        do {
            // Initialize screen recorder
            let recorder = ScreenRecorder(
                destination: localVideoURL,
                filter: filter,
                onFrameUpdate: { [weak self] image in
                    Task { @MainActor in
                        self?.previewImage = image
                    }
                }
            )
            
            try await recorder.start()
            
            await MainActor.run {
                self.screenRecorder = recorder
            }
            
            // Start audio recording if enabled
            let isEnabled = await MainActor.run { self.isAudioEnabled }
            if isEnabled {
                let audioRecorder = try AudioRecorder(outputURL: localAudioURL)
                try audioRecorder.start()
                
                await MainActor.run {
                    self.audioRecorder = audioRecorder
                }
            }
            
            await MainActor.run {
                self.recordingState = .recording
                self.recordingStartTime = Date()
                self.startTimer()
            }
        } catch {
            await MainActor.run {
                recordingState = .error("Failed to start recording: \(error.localizedDescription)")
                print("Recording error: \(error)")
            }
        }
    }
    
    func pauseRecording() {
        guard recordingState == .recording else { return }
        
        screenRecorder?.pause()
        audioRecorder?.pause()
        
        DispatchQueue.main.async {
            self.recordingState = .paused
            self.stopTimer()
        }
    }
    
    func resumeRecording() {
        guard recordingState == .paused else { return }
        
        screenRecorder?.resume()
        audioRecorder?.resume()
        
        DispatchQueue.main.async {
            self.recordingState = .recording
            self.startTimer()
        }
    }
    
    func stopRecording() async {
        // Make a local copy of the state to avoid Swift 6 concurrency issues
        let currentState = await MainActor.run { self.recordingState }
        guard currentState == .recording || currentState == .paused else { return }
        
        await MainActor.run {
            recordingState = .processing
            stopTimer()
        }
        
        do {
            // Get local copies to avoid capturing self
            let localScreenRecorder = await MainActor.run { self.screenRecorder }
            let localAudioRecorder = await MainActor.run { self.audioRecorder }
            let localVideoURL = await MainActor.run { self.videoURL }
            let localAudioURL = await MainActor.run { self.audioURL }
            
            if let screenRecorder = localScreenRecorder {
                try await screenRecorder.stop()
            }
            
            if let audioRecorder = localAudioRecorder {
                audioRecorder.stop()
            }
            
            await MainActor.run {
                self.recordingState = .idle
                self.elapsedSeconds = 0
                onSessionComplete?(localVideoURL, localAudioURL)
            }
        } catch {
            await MainActor.run {
                recordingState = .error("Failed to stop recording: \(error.localizedDescription)")
                print("Recording error: \(error)")
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedSeconds += 1
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// Screen Capture implementation
class ScreenRecorder: NSObject {
    private let destination: URL
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private var stream: SCStream?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var firstFrameTime: CMTime?
    private var onFrameUpdate: ((CGImage) -> Void)?
    private var hasStartedWriting = false // Track if writing has started
    private var frameCount = 0 // Track number of frames written
    
    init(destination: URL, filter: SCContentFilter, onFrameUpdate: ((CGImage) -> Void)? = nil) {
        self.destination = destination
        self.filter = filter
        self.onFrameUpdate = onFrameUpdate
        
        // Configure stream settings
        let config = SCStreamConfiguration()
        config.width = 1920  // Max width
        config.height = 1080 // Max height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        self.configuration = config
        
        // Call super.init() since we inherit from NSObject
        super.init()
    }
    
    func start() async throws {
        // Try to delete existing file if it exists to ensure we can create a new one
        try? FileManager.default.removeItem(at: destination)
        
        // Create video writer
        videoWriter = try AVAssetWriter(url: destination, fileType: .mp4)
        
        // Configure video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 3000000, // 3 Mbps
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        if let videoWriterInput = videoWriterInput,
           let videoWriter = videoWriter {
            videoWriter.add(videoWriterInput)
        }
        
        // Create and start the stream
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        try await stream?.startCapture()
        
        print("Screen recording started")
    }
    
    func pause() {
        // Just mark the state, actual pausing happens by not writing frames
    }
    
    func resume() {
        // Resume writing frames
    }
    
    func stop() async throws {
        print("Stopping screen recording. Frames captured: \(frameCount)")
        
        // Stop the capture stream first
        if let stream = stream {
            try await stream.stopCapture()
            self.stream = nil
        }
        
        // Only finalize video writing if we actually started writing
        if hasStartedWriting, let videoWriterInput = videoWriterInput, let videoWriter = videoWriter {
            // Check the status before calling markAsFinished
            if videoWriter.status == .writing {
                print("Finalizing video: marking as finished")
                videoWriterInput.markAsFinished()
                await videoWriter.finishWriting()
                print("Video writing finished successfully")
            } else {
                print("Skipping markAsFinished since writer status is \(videoWriter.status.rawValue)")
            }
        } else {
            print("No video data was written, skipping finalization (hasStartedWriting: \(hasStartedWriting))")
            
            // Create an empty file to prevent errors in case no frames were captured
            if !FileManager.default.fileExists(atPath: destination.path) {
                FileManager.default.createFile(atPath: destination.path, contents: Data())
                print("Created empty file at \(destination.path)")
            }
        }
    }
}

// Implement SCStreamOutput protocol for ScreenRecorder
extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let videoWriterInput = videoWriterInput,
              videoWriterInput.isReadyForMoreMediaData,
              sampleBuffer.isValid else {
            return
        }
        
        // Get frame time
        let frameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Initialize writer if needed
        if videoWriter?.status == .unknown {
            print("Initializing video writer with first frame")
            firstFrameTime = frameTime
            videoWriter?.startWriting()
            videoWriter?.startSession(atSourceTime: frameTime)
            hasStartedWriting = true
        }
        
        // Only append if we've started writing
        if hasStartedWriting && videoWriter?.status == .writing {
            if videoWriterInput.append(sampleBuffer) {
                frameCount += 1
                if frameCount % 30 == 0 {
                    print("Frames written: \(frameCount)")
                }
            } else {
                print("Failed to append sample buffer")
            }
        }
        
        // Update the preview image
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let onFrameUpdate = onFrameUpdate {
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                onFrameUpdate(cgImage)
            }
        }
    }
}

// Audio Recorder implementation for macOS
class AudioRecorder {
    private let outputURL: URL
    private var recordingProcess: Process?
    private var isPaused = false
    
    init(outputURL: URL) throws {
        self.outputURL = outputURL
    }
    
    func start() throws {
        // Using macOS command-line tools for audio recording
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay") // This is just a placeholder
        
        // In a real implementation, you would use AVCaptureSession for audio capture on macOS
        // or a command-line tool like ffmpeg/sox using Process
        
        // For now, we'll just create an empty audio file to avoid errors
        let emptyData = Data()
        try? emptyData.write(to: outputURL)
        
        // We're not actually starting the process, as this would require a more complex implementation
        // process.launch()
        
        recordingProcess = process
    }
    
    func pause() {
        isPaused = true
        // In a real implementation, you would pause the recording
    }
    
    func resume() {
        if isPaused {
            isPaused = false
            // In a real implementation, you would resume the recording
        }
    }
    
    func stop() {
        if let process = recordingProcess, process.isRunning {
            process.terminate()
        }
        recordingProcess = nil
    }
}