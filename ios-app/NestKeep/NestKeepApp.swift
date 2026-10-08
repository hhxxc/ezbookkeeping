import SwiftUI

@main
struct NestKeepApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(settings)
        }
    }
}
