import SwiftUI

struct ExportView: View {
    let session: RecordingSession
    
    @State private var selectedFormat: ExportService.ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportResult: ExportResult?
    
    enum ExportResult {
        case success(URL)
        case failure(String)
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Export Review")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let result = exportResult {
                exportResultView(result)
            } else {
                exportOptionsView
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isExporting {
                exportingOverlay
            }
        }
    }
    
    private var exportOptionsView: some View {
        VStack(spacing: 25) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Export Format")
                    .font(.headline)
                
                Picker("Format", selection: $selectedFormat) {
                    Text("Markdown Document").tag(ExportService.ExportFormat.markdown)
                    Text("HTML Document").tag(ExportService.ExportFormat.html)
                }
                .pickerStyle(.radioGroup)
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Export Preview")
                    .font(.headline)
                
                exportPreviewView
                    .frame(height: 200)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(10)
            }
            
            Button {
                exportDocument()
            } label: {
                Label("Export Document", systemImage: "square.and.arrow.up")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var exportPreviewView: some View {
        Group {
            if session.screenshots.isEmpty {
                Text("No content to preview. Generate analysis first.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("# App Review: \(session.name)")
                            .font(.title)
                        
                        Text("Date: \(session.formattedDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("## Review Timeline")
                            .font(.title2)
                        
                        ForEach(session.screenshots.prefix(2).sorted(by: { $0.timestamp < $1.timestamp })) { screenshot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("### \(screenshot.formattedTimestamp)")
                                    .font(.headline)
                                
                                if let thumbnailURL = screenshot.thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 120)
                                        .cornerRadius(4)
                                }
                                
                                Text("**Comments:**")
                                    .font(.subheadline)
                                
                                Text("*\"Sample commentary would appear here...\"*")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 10)
                        }
                        
                        Text("... and \(max(0, session.screenshots.count - 2)) more screenshots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
    
    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Exporting Document...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(25)
            .background(Color(.windowBackgroundColor).opacity(0.9))
            .cornerRadius(10)
            .shadow(radius: 10)
        }
    }
    
    private func exportResultView(_ result: ExportResult) -> some View {
        VStack(spacing: 20) {
            switch result {
            case .success(let url):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Export Successful!")
                    .font(.title2)
                
                Text("Saved to: \(url.path)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    Button("Open File") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Export Another") {
                    exportResult = nil
                }
                .padding(.top)
                
            case .failure(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Export Failed")
                    .font(.title2)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Try Again") {
                    exportResult = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func exportDocument() {
        let exportService = ExportService(session: session)
        
        isExporting = true
        
        if let window = NSApplication.shared.windows.first {
            exportService.showExportOptions(from: window) { url in
                isExporting = false
                
                if let url = url {
                    exportResult = .success(url)
                } else {
                    exportResult = .failure("Export was cancelled or failed")
                }
            }
        }
    }
}

#Preview {
    ExportView(session: RecordingSession())
}