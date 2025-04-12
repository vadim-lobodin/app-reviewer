import SwiftUI

@main
struct AppReviewerApp: App {
    @StateObject private var sessionManager = SessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording Session") {
                    sessionManager.createNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}