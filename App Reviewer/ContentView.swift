import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedTab: Tab = .record
    
    enum Tab {
        case record, review, export
    }
    
    var body: some View {
        NavigationSplitView {
            Sidebar(selectedTab: $selectedTab)
        } detail: {
            tabContent
                .frame(minWidth: 600, minHeight: 400)
        }
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .record:
            RecordingView()
        case .review:
            if let currentSession = sessionManager.currentSession {
                ReviewView(session: currentSession)
            } else {
                EmptyStateView(message: "No recording session to review")
            }
        case .export:
            if let currentSession = sessionManager.currentSession {
                ExportView(session: currentSession)
            } else {
                EmptyStateView(message: "No recording session to export")
            }
        }
    }
}

struct Sidebar: View {
    @Binding var selectedTab: ContentView.Tab
    @EnvironmentObject private var sessionManager: SessionManager
    
    var body: some View {
        List {
            NavigationLink(destination: EmptyView()) {
                Label("Record", systemImage: "record.circle")
            }
            .onTapGesture {
                selectedTab = .record
            }
            .background(selectedTab == .record ? Color.accentColor.opacity(0.2) : Color.clear)
            
            NavigationLink(destination: EmptyView()) {
                Label("Review", systemImage: "list.bullet.rectangle")
            }
            .onTapGesture {
                selectedTab = .review
            }
            .background(selectedTab == .review ? Color.accentColor.opacity(0.2) : Color.clear)
            
            NavigationLink(destination: EmptyView()) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .onTapGesture {
                selectedTab = .export
            }
            .background(selectedTab == .export ? Color.accentColor.opacity(0.2) : Color.clear)
            
            Section("Sessions") {
                ForEach(sessionManager.sessions) { session in
                    NavigationLink(destination: EmptyView()) {
                        HStack {
                            Text(session.name)
                            Spacer()
                            Text(session.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onTapGesture {
                        sessionManager.setCurrentSession(session)
                        selectedTab = .review
                    }
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200)
    }
}

struct EmptyStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.headline)
            
            Button("Start New Recording") {
                // Create a new recording session
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionManager())
}