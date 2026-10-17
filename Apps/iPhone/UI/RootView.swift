import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.disclaimerAccepted {
                DisclaimerView()
            } else {
                TabView {
                    TonightView()
                        .tabItem {
                            Label("Tonight", systemImage: "moon.stars.fill")
                        }
                    TrendsView()
                        .tabItem {
                            Label("Trends", systemImage: "chart.xyaxis.line")
                        }
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                }
                .tint(SleepTheme.accent)
            }
        }
        .background(SleepTheme.background.ignoresSafeArea())
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
}
