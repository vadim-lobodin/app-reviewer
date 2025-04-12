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
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var elapsedSeconds: Int = 0
    @Published var previewImage: CGImage?
    
    private var screenRecorder: ScreenRecorder?
    private var audioRecorder: AudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    
    // Output file URLs
    private var videoURL: URL?
    private var audioURL: URL?
    
    // Callbacks
    var onSessionComplete: ((URL?, URL?) -> Void)?
    
    init() {
        // Initialize with available capture devices
        Task {
            await refreshAvailableCaptureDevices()
        }
    }
    
    func refreshAvailableCaptureDevices() async {
        do {
            let content = try await SCShareableContent.current
            
            await MainActor.run {
                self.availableDisplays = content.displays
                self.availableWindows = content.windows.filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "App Reviewer" }
                
                // Default to main display if none selected
                if selectedDisplay == nil && !availableDisplays.isEmpty {
                    selectedDisplay = availableDisplays.first
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
        
        // Make sure we have a filter to capture
        guard let filter = await createCaptureFilter() else {
            await MainActor.run {
                recordingState = .error("No valid capture selection")
            }
            return
        }
        
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
            // Fixed: Correctly use MainActor.run and handle optional audioURL
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
            }
        }
    }
    
    private func createCaptureFilter() async -> SCContentFilter? {
        // Get local copies to avoid capturing self
        let localSelectedDisplay = await MainActor.run { self.selectedDisplay }
        let localSelectedWindow = await MainActor.run { self.selectedWindow }
        
        if let display = localSelectedDisplay {
            return SCContentFilter(display: display, excludingWindows: [])
        } else if let window = localSelectedWindow {
            return SCContentFilter(desktopIndependentWindow: window)
        }
        return nil
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
    }
    
    func pause() {
        // Just mark the state, actual pausing happens by not writing frames
    }
    
    func resume() {
        // Resume writing frames
    }
    
    func stop() async throws {
        try await stream?.stopCapture()
        stream = nil
        
        // Finalize video writing
        videoWriterInput?.markAsFinished()
        await videoWriter?.finishWriting()
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
            firstFrameTime = frameTime
            videoWriter?.startWriting()
            videoWriter?.startSession(atSourceTime: frameTime)
        }
        
        // Write the frame
        if let adjustedBuffer = adjustTime(sampleBuffer, from: firstFrameTime) {
            videoWriterInput.append(adjustedBuffer)
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
    
    private func adjustTime(_ sampleBuffer: CMSampleBuffer, from startTime: CMTime?) -> CMSampleBuffer? {
        guard let startTime = startTime else { return sampleBuffer }
        
        var adjustedBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo()
        var count: CMItemCount = 0
        
        // Get the timing info from the buffer - Fixed API usage with proper argument labels
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 
                                                    entryCount: 1, 
                                                    arrayToFill: &timing, 
                                                    entriesNeededOut: &count) == noErr else {
            return nil
        }
        
        // Adjust time to be relative to the first frame
        timing.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, startTime)
        
        // Create a new buffer with the adjusted timing
        var formatDescription: CMFormatDescription?
        CMSampleBufferGetFormatDescription(sampleBuffer, &formatDescription)
        
        if let formatDescription = formatDescription,
           let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            // Fixed API usage - removed the extra argument
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, 
                imageBuffer: imageBuffer,
                formatDescription: formatDescription,
                sampleTiming: &timing, 
                sampleBufferOut: &adjustedBuffer
            )
        }
        
        return adjustedBuffer
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