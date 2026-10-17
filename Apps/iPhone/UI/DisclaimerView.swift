import SwiftUI
import SleepCoachAnalysis

struct DisclaimerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            SleepTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(SleepTheme.accent)
                    Text("AI Sleep Coach")
                        .font(.largeTitle.bold())
                        .foregroundStyle(SleepTheme.cream)
                    Text("Please read this once before using the app.")
                        .foregroundStyle(SleepTheme.muted)
                    Text(SafetyCopy.productDisclaimer)
                        .font(.body)
                        .foregroundStyle(SleepTheme.cream.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.acceptDisclaimer()
                    } label: {
                        Text("I understand — continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SleepTheme.accent)
                    .foregroundStyle(.black)
                }
                .padding(24)
            }
        }
    }
}

#Preview {
    DisclaimerView()
        .environment(AppModel.preview)
}
