import Foundation
import AppKit
import UniformTypeIdentifiers  // Added import for UTType

class ExportService {
    enum ExportFormat {
        case markdown
        case html
    }
    
    enum ExportError: Error {
        case sessionEmpty
        case exportFailed(String)
    }
    
    private let session: RecordingSession
    
    init(session: RecordingSession) {
        self.session = session
    }
    
    func exportSession(as format: ExportFormat = .markdown) async throws -> URL {
        guard !session.screenshots.isEmpty && !session.transcriptions.isEmpty else {
            throw ExportError.sessionEmpty
        }
        
        // Create a temporary directory for the export
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Prepare export content
        let content: String
        let fileExtension: String
        let mediaDirectory: URL
        
        switch format {
        case .markdown:
            mediaDirectory = tempDirectory.appendingPathComponent("media")
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            
            content = try createMarkdownContent(mediaDirectory: mediaDirectory)
            fileExtension = "md"
            
        case .html:
            mediaDirectory = tempDirectory.appendingPathComponent("media")
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            
            content = try createHTMLContent(mediaDirectory: mediaDirectory)
            fileExtension = "html"
        }
        
        // Create the output file
        let outputFileName = "App_Review_\(session.id.uuidString.prefix(8)).\(fileExtension)"
        let outputURL = tempDirectory.appendingPathComponent(outputFileName)
        
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        
        return outputURL
    }
    
    private func createMarkdownContent(mediaDirectory: URL) throws -> String {
        let fileManager = FileManager.default
        var markdown = "# App Review: \(session.name)\n\n"
        markdown += "Date: \(session.formattedDate)\n\n"
        
        markdown += "## Review Timeline\n\n"
        
        // Sort screenshots by timestamp
        let sortedScreenshots = session.screenshots.sorted { $0.timestamp < $1.timestamp }
        
        for screenshot in sortedScreenshots {
            // Copy the image to the media directory
            let imageDestination = mediaDirectory.appendingPathComponent("screenshot_\(Int(screenshot.timestamp)).png")
            try fileManager.copyItem(at: screenshot.imageURL, to: imageDestination)
            
            markdown += "### \(screenshot.formattedTimestamp)\n\n"
            markdown += "![Screenshot at \(screenshot.formattedTimestamp)](media/screenshot_\(Int(screenshot.timestamp)).png)\n\n"
            
            // Find transcriptions that occurred around this screenshot time
            let relatedTranscriptions = session.transcriptions.filter { transcription in
                transcription.startTime <= screenshot.timestamp && 
                transcription.endTime >= screenshot.timestamp
            }
            
            if !relatedTranscriptions.isEmpty {
                markdown += "**Comments:**\n\n"
                
                for transcription in relatedTranscriptions {
                    if let summary = transcription.summary {
                        markdown += "- *\"\(summary)\"*\n"
                    } else {
                        markdown += "- *\"\(transcription.text)\"*\n"
                    }
                }
                
                markdown += "\n"
            }
            
            markdown += "---\n\n"
        }
        
        markdown += "## Full Transcript\n\n"
        
        let sortedTranscriptions = session.transcriptions.sorted { $0.startTime < $1.startTime }
        
        for transcription in sortedTranscriptions {
            markdown += "**[\(transcription.formattedTimeRange)]** \(transcription.text)\n\n"
        }
        
        return markdown
    }
    
    private func createHTMLContent(mediaDirectory: URL) throws -> String {
        let fileManager = FileManager.default
        
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>App Review: \(session.name)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.6; max-width: 1200px; margin: 0 auto; padding: 20px; }
                h1, h2, h3 { color: #333; }
                .screenshot { max-width: 100%; height: auto; border: 1px solid #ddd; }
                .timestamp { color: #666; font-weight: bold; }
                .comment { background-color: #f8f8f8; border-left: 4px solid #0066cc; padding: 10px; margin: 10px 0; }
                .summary { font-style: italic; color: #333; }
                .divider { border-bottom: 1px solid #eee; margin: 30px 0; }
                .transcript { background-color: #f9f9f9; padding: 20px; margin-top: 30px; }
            </style>
        </head>
        <body>
            <h1>App Review: \(session.name)</h1>
            <p>Date: \(session.formattedDate)</p>
            
            <h2>Review Timeline</h2>
        """
        
        // Sort screenshots by timestamp
        let sortedScreenshots = session.screenshots.sorted { $0.timestamp < $1.timestamp }
        
        for screenshot in sortedScreenshots {
            // Copy the image to the media directory
            let imageDestination = mediaDirectory.appendingPathComponent("screenshot_\(Int(screenshot.timestamp)).png")
            try fileManager.copyItem(at: screenshot.imageURL, to: imageDestination)
            
            html += """
            <div class="review-item">
                <h3 class="timestamp">\(screenshot.formattedTimestamp)</h3>
                <img class="screenshot" src="media/screenshot_\(Int(screenshot.timestamp)).png" alt="Screenshot at \(screenshot.formattedTimestamp)">
            """
            
            // Find transcriptions that occurred around this screenshot time
            let relatedTranscriptions = session.transcriptions.filter { transcription in
                transcription.startTime <= screenshot.timestamp && 
                transcription.endTime >= screenshot.timestamp
            }
            
            if !relatedTranscriptions.isEmpty {
                html += "<div class=\"comments\">"
                html += "<h4>Comments:</h4>"
                
                for transcription in relatedTranscriptions {
                    html += "<div class=\"comment\">"
                    if let summary = transcription.summary {
                        html += "<p class=\"summary\">\"\(summary)\"</p>"
                    } else {
                        html += "<p class=\"summary\">\"\(transcription.text)\"</p>"
                    }
                    html += "</div>"
                }
                
                html += "</div>"
            }
            
            html += """
            </div>
            <div class="divider"></div>
            """
        }
        
        html += """
        <div class="transcript">
            <h2>Full Transcript</h2>
        """
        
        let sortedTranscriptions = session.transcriptions.sorted { $0.startTime < $1.startTime }
        
        for transcription in sortedTranscriptions {
            html += """
            <p><span class="timestamp">[\(transcription.formattedTimeRange)]</span> \(transcription.text)</p>
            """
        }
        
        html += """
        </div>
        </body>
        </html>
        """
        
        return html
    }
    
    func showExportOptions(from window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.markdown, .html]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "App_Review_\(session.name)"
        
        let result = savePanel.runModal()
        
        if result == .OK, let url = savePanel.url {
            Task {
                do {
                    let format: ExportFormat = url.pathExtension.lowercased() == "html" ? .html : .markdown
                    let exportedURL = try await exportSession(as: format)
                    
                    // Copy to the user-selected location
                    try FileManager.default.copyItem(at: exportedURL, to: url)
                    
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: exportedURL)
                    
                    DispatchQueue.main.async {
                        completion(url)
                    }
                } catch {
                    print("Export failed: \(error)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        } else {
            completion(nil)
        }
    }
}

// Add UTType extensions for export options
extension UTType {
    static var markdown: UTType {
        UTType(filenameExtension: "md", conformingTo: .text)!
    }
}