import Foundation
import SwiftUI

struct RecordingSession: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var name: String
    
    // Recording paths
    var videoURL: URL?
    var audioURL: URL?
    
    // Analysis results
    var screenshots: [Screenshot] = []
    var transcriptions: [Transcription] = []
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    init(id: UUID = UUID(), name: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.name = name ?? "Session \(Self.dateFormatter.string(from: createdAt))"
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct Screenshot: Identifiable, Codable {
    // Changed to vars to allow Codable to decode them
    var id: UUID
    let timestamp: TimeInterval
    let imageURL: URL
    let thumbnailURL: URL?
    
    // Initialize with default value
    init(id: UUID = UUID(), timestamp: TimeInterval, imageURL: URL, thumbnailURL: URL?) {
        self.id = id
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
    }
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct Transcription: Identifiable, Codable {
    // Changed to vars to allow Codable to decode them
    var id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    var summary: String?
    
    // Initialize with default value
    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String, summary: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.summary = summary
    }
    
    var formattedTimeRange: String {
        let startMinutes = Int(startTime) / 60
        let startSeconds = Int(startTime) % 60
        let endMinutes = Int(endTime) / 60
        let endSeconds = Int(endTime) % 60
        return String(format: "%02d:%02d - %02d:%02d", startMinutes, startSeconds, endMinutes, endSeconds)
    }
}