import SwiftUI
import SleepCoachAnalysis

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return NavigationStack {
            ZStack {
                SleepTheme.background.ignoresSafeArea()
                List {
                    Section("Data") {
                        Toggle("Use sample data", isOn: $model.useSampleData)
                            .onChange(of: model.useSampleData) { _, enabled in
                                Task {
                                    if enabled {
                                        model.loadSampleData()
                                    } else {
                                        await model.refresh()
                                    }
                                }
                            }
                        Button("Connect Apple Health") {
                            Task { await model.requestHealthAccess() }
                        }
                        if let error = model.lastError {
                            Text(error).font(.caption).foregroundStyle(SleepTheme.warning)
                        }
                    }

                    Section("Apple Watch") {
                        Text("Start an overnight session on the Watch app if you want wrist-motion restlessness. Sleep stages still come from Apple’s own Sleep tracking whenever they exist, even without the companion session.")
                            .font(.footnote)
                            .foregroundStyle(SleepTheme.muted)
                    }

                    Section("Sleep Apnoea notifications") {
                        Text(SafetyCopy.enableAppleSleepApnoeaHelp)
                            .font(.footnote)
                    }

                    Section("Medical disclaimer") {
                        Text(SafetyCopy.productDisclaimer)
                            .font(.footnote)
                    }

                    Section("Privacy") {
                        Text("Analysis runs on this iPhone. Nights stay in HealthKit and in the app’s on-device store. Nothing is uploaded.")
                            .font(.footnote)
                    }

                    Section("About") {
                        LabeledContent("App", value: "AI Sleep Coach")
                        LabeledContent("For", value: "Stefan Istoc")
                        Link("GitHub repository", destination: URL(string: "https://github.com/stefandevelops/ai-sleep-coach")!)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.preview)
}
