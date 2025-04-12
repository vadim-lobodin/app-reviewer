import Foundation
import SwiftUI

class SessionManager: ObservableObject {
    @Published var sessions: [RecordingSession] = []
    @Published var currentSession: RecordingSession?
    
    private let sessionsDirectoryURL: URL
    
    init() {
        // Create app documents directory if needed
        let fileManager = FileManager.default
        
        // Get the app group container or fall back to documents directory
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "com.yourcompany.AppReviewer") {
            sessionsDirectoryURL = containerURL.appendingPathComponent("Sessions", isDirectory: true)
        } else {
            // Use the application support directory instead of documents
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            sessionsDirectoryURL = appSupportURL.appendingPathComponent("Sessions", isDirectory: true)
        }
        
        // Create the Sessions directory if it doesn't exist (fixed)
        if !fileManager.fileExists(atPath: sessionsDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
                print("Created sessions directory at: \(sessionsDirectoryURL.path)")
            } catch {
                print("Failed to create sessions directory: \(error)")
            }
        }
        
        // Load existing sessions
        loadSessions()
    }
    
    func createNewSession() {
        let newSession = RecordingSession()
        createDirectoryForSession(newSession)
        sessions.append(newSession)
        currentSession = newSession
        saveSessionMetadata(newSession)
    }
    
    func setCurrentSession(_ session: RecordingSession) {
        currentSession = session
    }
    
    func updateSession(_ session: RecordingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            
            if currentSession?.id == session.id {
                currentSession = session
            }
            
            saveSessionMetadata(session)
        }
    }
    
    func deleteSession(_ session: RecordingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: index)
            
            if currentSession?.id == session.id {
                currentSession = nil
            }
            
            // Delete directory
            let sessionDir = sessionDirectoryURL(for: session)
            try? FileManager.default.removeItem(at: sessionDir)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSessions() {
        let fileManager = FileManager.default
        
        do {
            // Check if the sessions directory exists before trying to enumerate it
            if !fileManager.fileExists(atPath: sessionsDirectoryURL.path) {
                print("Sessions directory doesn't exist yet, no sessions to load")
                return
            }
            
            let sessionDirs = try fileManager.contentsOfDirectory(at: sessionsDirectoryURL, includingPropertiesForKeys: nil)
            
            let loadedSessions = sessionDirs.compactMap { dirURL -> RecordingSession? in
                let metadataURL = dirURL.appendingPathComponent("metadata.json")
                
                guard let data = try? Data(contentsOf: metadataURL),
                      let decodedSession = try? JSONDecoder().decode(RecordingSession.self, from: data) else {
                    return nil
                }
                
                return decodedSession
            }
            
            DispatchQueue.main.async {
                self.sessions = loadedSessions.sorted(by: { $0.createdAt > $1.createdAt })
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
    
    private func saveSessionMetadata(_ session: RecordingSession) {
        let encoder = JSONEncoder()
        
        do {
            let data = try encoder.encode(session)
            let metadataURL = sessionDirectoryURL(for: session).appendingPathComponent("metadata.json")
            try data.write(to: metadataURL)
        } catch {
            print("Failed to save session metadata: \(error)")
        }
    }
    
    private func createDirectoryForSession(_ session: RecordingSession) {
        let sessionDir = sessionDirectoryURL(for: session)
        
        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            
            // Create subdirectories
            try FileManager.default.createDirectory(at: sessionDir.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionDir.appendingPathComponent("media"), withIntermediateDirectories: true)
        } catch {
            print("Failed to create session directory: \(error)")
        }
    }
    
    // Changed from private to internal so AnalysisEngine can access it
    func sessionDirectoryURL(for session: RecordingSession) -> URL {
        return sessionsDirectoryURL.appendingPathComponent(session.id.uuidString, isDirectory: true)
    }
}