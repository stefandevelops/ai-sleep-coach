import SwiftUI

@main
struct AISleepCoachWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
        }
    }
}
