import SwiftUI

@main
struct ImmichApp: App {
    @State private var session = SessionManager()

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(session)
                .task { await session.restore() }
        }
    }
}
