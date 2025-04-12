import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var recordingManager = RecordingManager()
    @State private var showingAnalysisView = false
    
    var body: some View {
        VStack(spacing: 20) {
            if recordingManager.recordingState == .idle || recordingManager.recordingState == .preparing {
                setupView
            } else {
                recordingInProgressView
            }
        }
        .padding()
        .onAppear {
            Task {
                await recordingManager.refreshAvailableCaptureDevices()
            }
            
            // Configure callback for when recording session completes
            recordingManager.onSessionComplete = { videoURL, audioURL in
                // Update the current session with recording URLs
                if let videoURL = videoURL, 
                   let audioURL = audioURL,
                   let currentSession = sessionManager.currentSession {
                    
                    var updatedSession = currentSession
                    updatedSession.videoURL = videoURL
                    updatedSession.audioURL = audioURL
                    
                    sessionManager.updateSession(updatedSession)
                    
                    // Show analysis view
                    showingAnalysisView = true
                }
            }
        }
        .sheet(isPresented: $showingAnalysisView) {
            if let currentSession = sessionManager.currentSession {
                AnalysisView(session: currentSession)
            }
        }
    }
    
    private var setupView: some View {
        VStack(spacing: 30) {
            Text("Create New Recording")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Select what to record:")
                    .font(.headline)
                
                Picker("Capture Type", selection: $recordingManager.selectedDisplay) {
                    Text("Select display...").tag(nil as SCDisplay?)
                    
                    ForEach(recordingManager.availableDisplays, id: \.displayID) { display in
                        Text("Display: \(display.width) × \(display.height)")
                            .tag(Optional(display))
                    }
                }
                .frame(width: 400)
                
                Picker("Window", selection: $recordingManager.selectedWindow) {
                    Text("Select window...").tag(nil as SCWindow?)
                    
                    ForEach(recordingManager.availableWindows, id: \.windowID) { window in
                        if let appName = window.owningApplication?.applicationName {
                            Text("Window: \(appName) - \(window.title)")
                                .tag(Optional(window))
                        }
                    }
                }
                .frame(width: 400)
                
                Toggle("Record audio commentary", isOn: $recordingManager.isAudioEnabled)
                    .padding(.top, 10)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.windowBackgroundColor))
            )
            
            Button {
                Task { await recordingManager.startRecording() }
            } label: {
                Text("Start Recording")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 200)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(recordingManager.selectedDisplay == nil && recordingManager.selectedWindow == nil)
        }
    }
    
    private var recordingInProgressView: some View {
        VStack(spacing: 20) {
            if let previewImage = recordingManager.previewImage {
                Image(previewImage, scale: 1.0, label: Text("Preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 300)
                    .cornerRadius(8)
                    .overlay(
                        Text("Recording in progress...")
                            .foregroundColor(.secondary)
                    )
            }
            
            Text("Recording Time: \(formattedTime(recordingManager.elapsedSeconds))")
                .font(.title)
                .foregroundColor(.primary)
                .monospacedDigit()
            
            HStack(spacing: 30) {
                if recordingManager.recordingState == .recording {
                    Button {
                        recordingManager.pauseRecording()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 150)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                } else if recordingManager.recordingState == .paused {
                    Button {
                        recordingManager.resumeRecording()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 150)
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }
                
                Button {
                    Task { await recordingManager.stopRecording() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 150)
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct AnalysisView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var analysisEngine: AnalysisEngine
    @Environment(\.dismiss) private var dismiss
    
    init(session: RecordingSession) {
        _analysisEngine = StateObject(wrappedValue: AnalysisEngine(session: session, sessionManager: SessionManager()))
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Processing Recording")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if analysisEngine.state == .analyzing {
                ProgressView("Analyzing content...", value: analysisEngine.progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 300)
                
                Text("\(Int(analysisEngine.progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else if analysisEngine.state == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Analysis Complete!")
                    .font(.headline)
                
                Button("View Results") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if case .error(let message) = analysisEngine.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Analysis Failed")
                    .font(.headline)
                
                Text(message)
                    .foregroundColor(.secondary)
                
                Button("Try Again") {
                    Task {
                        await analysisEngine.analyzeSession()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Start Analysis") {
                    Task {
                        await analysisEngine.analyzeSession()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .onAppear {
            Task {
                if analysisEngine.state == .idle {
                    await analysisEngine.analyzeSession()
                }
            }
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(SessionManager())
}