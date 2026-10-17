import SwiftUI

@main
struct AISleepCoachApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task {
                    await model.bootstrap()
                }
        }
    }
}
