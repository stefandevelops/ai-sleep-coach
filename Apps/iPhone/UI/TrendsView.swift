import Charts
import SwiftUI
import SleepCoachAnalysis

struct TrendsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                SleepTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summary
                        SleepCard {
                            Text("Sleep quality")
                                .font(.headline)
                                .foregroundStyle(SleepTheme.cream)
                            Chart(model.trendPoints) { point in
                                LineMark(
                                    x: .value("Day", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(SleepTheme.accent)
                                .interpolationMethod(.catmullRom)
                                AreaMark(
                                    x: .value("Day", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(SleepTheme.accent.opacity(0.18))
                                .interpolationMethod(.catmullRom)
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 180)
                            .padding(.top, 8)
                        }
                        SleepCard {
                            Text("Time asleep")
                                .font(.headline)
                                .foregroundStyle(SleepTheme.cream)
                            Chart(model.trendPoints) { point in
                                BarMark(
                                    x: .value("Day", point.date),
                                    y: .value("Hours", point.asleepHours)
                                )
                                .foregroundStyle(SleepTheme.accent.opacity(0.85))
                            }
                            .frame(height: 140)
                        }
                        flagsSummary
                        Text("Trends are descriptive. They are not a 30-day medical evaluation.")
                            .font(.caption)
                            .foregroundStyle(SleepTheme.muted)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle("30 days")
        }
    }

    private var summary: some View {
        let scores = model.trendPoints.map(\.score)
        let hours = model.trendPoints.map(\.asleepHours)
        let avgScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let avgHours = hours.isEmpty ? 0 : hours.reduce(0, +) / Double(hours.count)
        return HStack(spacing: 10) {
            SleepCard {
                Text("Average score").font(.caption).foregroundStyle(SleepTheme.muted)
                Text("\(avgScore)").font(.title.bold()).foregroundStyle(SleepTheme.cream)
            }
            SleepCard {
                Text("Average asleep").font(.caption).foregroundStyle(SleepTheme.muted)
                Text(String(format: "%.1fh", avgHours)).font(.title.bold()).foregroundStyle(SleepTheme.cream)
            }
        }
    }

    private var flagsSummary: some View {
        let flaggedNights = model.nights.filter { night in
            guard let analysis = model.analyses[night.id] else { return false }
            return !analysis.flaggedEvents.isEmpty
        }
        return SleepCard {
            Text("Possible breathing flags")
                .font(.headline)
                .foregroundStyle(SleepTheme.cream)
            Text("\(flaggedNights.count) of the last \(model.nights.count) nights had at least one heuristic flag. That is not a diagnosis.")
                .font(.footnote)
                .foregroundStyle(SleepTheme.muted)
            Text(SafetyCopy.enableAppleSleepApnoeaHelp)
                .font(.footnote)
                .foregroundStyle(SleepTheme.warning)
                .padding(.top, 4)
        }
    }
}

#Preview {
    TrendsView()
        .environment(AppModel.preview)
}
