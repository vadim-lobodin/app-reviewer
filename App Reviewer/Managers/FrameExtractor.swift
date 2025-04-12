import Foundation
import AVFoundation
import CoreImage
import UniformTypeIdentifiers

class FrameExtractor {
    private let videoURL: URL
    private let interval: TimeInterval
    private let outputDirectory: URL
    
    init(videoURL: URL, interval: TimeInterval, outputDirectory: URL) {
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
        
        var screenshots: [Screenshot] = []
        
        // Extract frames at regular intervals
        var time: TimeInterval = 0
        while time < durationSeconds {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            
            do {
                let imageRef = try await generator.image(at: cmTime)
                let frame = CIImage(cgImage: imageRef.image)
                
                // Save full resolution image
                let imageURL = outputDirectory.appendingPathComponent("frame_\(Int(time)).png")
                
                try saveCGImage(imageRef.image, to: imageURL)
                
                // Create and save thumbnail
                let thumbnailURL = outputDirectory.appendingPathComponent("thumb_\(Int(time)).png")
                if let thumbnail = createThumbnail(from: imageRef.image, maxSize: 320) {
                    try saveCGImage(thumbnail, to: thumbnailURL)
                    
                    // Create screenshot object
                    let screenshot = Screenshot(
                        timestamp: time,
                        imageURL: imageURL,
                        thumbnailURL: thumbnailURL
                    )
                    screenshots.append(screenshot)
                }
            } catch {
                print("Failed to generate image at time \(time): \(error)")
            }
            
            // Move to next interval
            time += interval
        }
        
        return screenshots
    }
    
    private func saveCGImage(_ image: CGImage, to url: URL) throws {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()
        
        // In macOS 12 and later, use UTType.png
        if #available(macOS 12.0, *) {
            try context.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(), options: [:])
        } else {
            // Fallback for older macOS versions
            try context.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        }
    }
    
    private func createThumbnail(from image: CGImage, maxSize: CGFloat) -> CGImage? {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)
        
        // Calculate new size while maintaining aspect ratio
        let aspectRatio = originalWidth / originalHeight
        
        let newWidth: CGFloat
        let newHeight: CGFloat
        
        if originalWidth > originalHeight {
            newWidth = min(maxSize, originalWidth)
            newHeight = newWidth / aspectRatio
        } else {
            newHeight = min(maxSize, originalHeight)
            newWidth = newHeight * aspectRatio
        }
        
        let context = CGContext(
            data: nil,
            width: Int(newWidth),
            height: Int(newHeight),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        )
        
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context?.makeImage()
    }
}