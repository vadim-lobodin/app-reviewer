import Foundation
import AVFoundation
import CoreImage
import CoreGraphics

class FrameExtractor {
    enum FrameExtractionError: Error {
        case invalidVideoFile
        case extractionFailed(String)
    }
    
    private let videoURL: URL
    private let interval: TimeInterval
    private let outputDirectory: URL
    
    init(videoURL: URL, interval: TimeInterval = 5.0, outputDirectory: URL) {
        self.videoURL = videoURL
        self.interval = interval
        self.outputDirectory = outputDirectory
    }
    
    func extractFrames() async throws -> [Screenshot] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Create array of times to sample
        var times: [CMTime] = []
        var currentTime: TimeInterval = 0
        
        while currentTime < durationSeconds {
            times.append(CMTime(seconds: currentTime, preferredTimescale: 600))
            currentTime += interval
        }
        
        // Ensure we capture the last frame
        if durationSeconds > 0 && (durationSeconds - currentTime).magnitude > 0.1 {
            times.append(CMTime(seconds: durationSeconds, preferredTimescale: 600))
        }
        
        // Create directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        // Extract images
        var screenshots: [Screenshot] = []
        
        for (index, time) in times.enumerated() {
            do {
                let imageRef = try generator.copyCGImage(at: time, actualTime: nil)
                let timeValue = CMTimeGetSeconds(time)
                
                // Save full-size image
                let imageName = "screenshot_\(index)_\(Int(timeValue)).png"
                let imageURL = outputDirectory.appendingPathComponent(imageName)
                
                if let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, kUTTypePNG, 1, nil) {
                    CGImageDestinationAddImage(destination, imageRef, nil)
                    if CGImageDestinationFinalize(destination) {
                        // Create thumbnail
                        let thumbnailURL = try createThumbnail(from: imageRef, index: index, time: timeValue)
                        
                        let screenshot = Screenshot(
                            timestamp: timeValue,
                            imageURL: imageURL,
                            thumbnailURL: thumbnailURL
                        )
                        
                        screenshots.append(screenshot)
                    }
                }
            } catch {
                print("Warning: Failed to extract frame at \(time): \(error)")
            }
        }
        
        if screenshots.isEmpty {
            throw FrameExtractionError.extractionFailed("No frames could be extracted")
        }
        
        return screenshots
    }
    
    private func createThumbnail(from image: CGImage, index: Int, time: TimeInterval) throws -> URL {
        // Create a smaller thumbnail image
        let thumbnailSize = CGSize(width: 320, height: 180)
        let thumbnailContext = CGContext(
            data: nil,
            width: Int(thumbnailSize.width),
            height: Int(thumbnailSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        
        guard let thumbnailContext = thumbnailContext else {
            throw FrameExtractionError.extractionFailed("Failed to create thumbnail context")
        }
        
        thumbnailContext.interpolationQuality = .high
        thumbnailContext.draw(image, in: CGRect(origin: .zero, size: thumbnailSize))
        
        guard let thumbnailImage = thumbnailContext.makeImage() else {
            throw FrameExtractionError.extractionFailed("Failed to create thumbnail image")
        }
        
        // Save thumbnail
        let thumbnailName = "thumbnail_\(index)_\(Int(time)).png"
        let thumbnailURL = outputDirectory.appendingPathComponent(thumbnailName)
        
        guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, kUTTypePNG, 1, nil) else {
            throw FrameExtractionError.extractionFailed("Failed to create thumbnail destination")
        }
        
        CGImageDestinationAddImage(destination, thumbnailImage, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            throw FrameExtractionError.extractionFailed("Failed to write thumbnail")
        }
        
        return thumbnailURL
    }
}