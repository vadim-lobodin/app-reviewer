import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import SwiftUI

class RecordingManager: ObservableObject {
    enum RecordingState {
        case idle
        case preparing
        case recording
        case paused
        case processing
        case error(String)
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
        guard recordingState == .idle || recordingState == .paused else { return }
        
        await MainActor.run {
            recordingState = .preparing
        }
        
        // Prepare file URLs for output
        let documentsPath = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        
        videoURL = documentsPath.appendingPathComponent("recording_\(timestamp).mp4")
        audioURL = documentsPath.appendingPathComponent("audio_\(timestamp).m4a")
        
        // Make sure we have a filter to capture
        guard let filter = createCaptureFilter() else {
            await MainActor.run {
                recordingState = .error("No valid capture selection")
            }
            return
        }
        
        do {
            // Initialize screen recorder
            let recorder = ScreenRecorder(
                destination: videoURL!,
                filter: filter,
                onFrameUpdate: { [weak self] image in
                    DispatchQueue.main.async {
                        self?.previewImage = image
                    }
                }
            )
            
            try await recorder.start()
            self.screenRecorder = recorder
            
            // Start audio recording if enabled
            if isAudioEnabled, let audioUrl = audioURL {
                let audioRecorder = AudioRecorder(outputURL: audioUrl)
                try audioRecorder.start()
                self.audioRecorder = audioRecorder
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
        guard recordingState == .recording || recordingState == .paused else { return }
        
        await MainActor.run {
            recordingState = .processing
            stopTimer()
        }
        
        do {
            if let screenRecorder = screenRecorder {
                try await screenRecorder.stop()
            }
            
            if let audioRecorder = audioRecorder {
                audioRecorder.stop()
            }
            
            await MainActor.run {
                self.recordingState = .idle
                self.elapsedSeconds = 0
                onSessionComplete?(videoURL, audioURL)
            }
        } catch {
            await MainActor.run {
                recordingState = .error("Failed to stop recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func createCaptureFilter() -> SCContentFilter? {
        if let display = selectedDisplay {
            return SCContentFilter(display: display, excludingWindows: [])
        } else if let window = selectedWindow {
            return SCContentFilter(window: window)
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
class ScreenRecorder {
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
        
        // Get the timing info from the buffer
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 1, &timing, &count) == noErr else {
            return nil
        }
        
        // Adjust time to be relative to the first frame
        timing.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, startTime)
        
        // Create a new buffer with the adjusted timing
        var formatDescription: CMFormatDescription?
        CMSampleBufferGetFormatDescription(sampleBuffer, formatDescriptionOut: &formatDescription)
        
        if let formatDescription = formatDescription,
           let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: CMSampleBufferGetImageBuffer(sampleBuffer)!,
                formatDescription: formatDescription,
                sampleTimingArray: [timing],
                sampleTimingArrayEntryCount: 1,
                sampleTimingArrayOut: nil,
                sampleBufferOut: &adjustedBuffer
            )
        }
        
        return adjustedBuffer
    }
}

// Audio Recorder implementation
class AudioRecorder {
    private let audioRecorder: AVAudioRecorder
    private var isPaused = false
    
    init(outputURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        
        self.audioRecorder = try AVAudioRecorder(url: outputURL, settings: settings)
        self.audioRecorder.prepareToRecord()
    }
    
    func start() throws {
        audioRecorder.record()
    }
    
    func pause() {
        isPaused = true
        audioRecorder.pause()
    }
    
    func resume() {
        if isPaused {
            isPaused = false
            audioRecorder.record()
        }
    }
    
    func stop() {
        audioRecorder.stop()
        
        // Reset audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}