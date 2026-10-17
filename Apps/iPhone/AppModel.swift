import Foundation
import Observation
import SleepCoachAnalysis
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var useSampleData: Bool {
        didSet { UserDefaults.standard.set(useSampleData, forKey: Keys.sampleData) }
    }

    var disclaimerAccepted: Bool {
        didSet { UserDefaults.standard.set(disclaimerAccepted, forKey: Keys.disclaimer) }
    }

    var nights: [SleepNight] = []
    var analyses: [UUID: SleepAnalysisResult] = [:]
    var healthAuthorized = false
    var lastError: String?
    var isRefreshing = false
    var pendingDrafts: [SleepSessionDraft] = []

    let analysisModel: any SleepAnalysisModel
    let merger = SleepNightMerger()
    let store = NightStore()
    let health = HealthKitService()
    let phoneConnectivity = PhoneConnectivity()

    static var preview: AppModel {
        let model = AppModel(analysisModel: HeuristicSleepAnalysisModel())
        model.useSampleData = true
        model.disclaimerAccepted = true
        model.loadSampleData()
        return model
    }

    init(analysisModel: any SleepAnalysisModel = HeuristicSleepAnalysisModel()) {
        self.analysisModel = analysisModel
        self.useSampleData = UserDefaults.standard.object(forKey: Keys.sampleData) as? Bool ?? true
        self.disclaimerAccepted = UserDefaults.standard.bool(forKey: Keys.disclaimer)
    }

    var lastNight: SleepNight? { nights.last }
    var lastAnalysis: SleepAnalysisResult? {
        lastNight.flatMap { analyses[$0.id] }
    }

    var trendPoints: [TrendPoint] {
        nights.suffix(30).map { night in
            TrendPoint(
                date: night.morningDate,
                score: analyses[night.id]?.score.total ?? 0,
                asleepHours: night.asleepDuration / 3600,
                disturbanceIndex: analyses[night.id]?.possibleDisturbanceIndex ?? 0
            )
        }
    }

    func bootstrap() async {
        phoneConnectivity.onDraft = { [weak self] draft in
            Task { @MainActor in
                self?.ingest(draft: draft)
            }
        }
        phoneConnectivity.activate()
        pendingDrafts = store.loadDrafts()
        if useSampleData {
            loadSampleData()
            return
        }
        await refreshFromHealth()
    }

    func loadSampleData() {
        let factory = SampleDataFactory(seed: 11)
        nights = factory.lastNights(count: 30)
        recomputeAnalyses()
        publishWatchScore()
    }

    func refresh() async {
        if useSampleData {
            loadSampleData()
            return
        }
        await refreshFromHealth()
    }

    func requestHealthAccess() async {
        do {
            try await health.requestAuthorization()
            healthAuthorized = true
            useSampleData = false
            await refreshFromHealth()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func acceptDisclaimer() {
        disclaimerAccepted = true
    }

    private func refreshFromHealth() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            healthAuthorized = try await health.isAuthorized()
            let appleNights = try await health.loadRecentNights(days: 30)
            var merged: [SleepNight] = []
            let drafts = store.loadDrafts()
            pendingDrafts = drafts
            for apple in appleNights {
                let match = drafts.first { draft in
                    abs(draft.end.timeIntervalSince(apple.inBedEnd)) < 4 * 3600
                        || abs(draft.start.timeIntervalSince(apple.inBedStart)) < 4 * 3600
                }
                let coach = match.map {
                    $0.asCoachNight(morning: apple.morningDate)
                }
                if let night = merger.merge(apple: apple, coach: coach) {
                    merged.append(night)
                }
            }
            for draft in drafts where !merged.contains(where: { $0.id == draft.id || abs($0.inBedStart.timeIntervalSince(draft.start)) < 3600 }) {
                merged.append(draft.asCoachNight(morning: Calendar.current.startOfDay(for: draft.end)))
            }
            nights = merged.sorted { $0.morningDate < $1.morningDate }
            if let last = nights.last {
                try await maybeWriteCoachSleep(last)
            }
            recomputeAnalyses()
            publishWatchScore()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if nights.isEmpty {
                loadSampleData()
            }
        }
    }

    private func ingest(draft: SleepSessionDraft) {
        store.save(draft: draft)
        pendingDrafts = store.loadDrafts()
        Task { await refresh() }
    }

    private func maybeWriteCoachSleep(_ night: SleepNight) async throws {
        let apple = try await health.appleNight(on: night.morningDate)
        let coach: SleepNight? = night.provenance.sleepStagesSource == .aiSleepCoachSession ? night : nil
        guard merger.shouldWriteCoachSleepAnalysis(apple: apple, coach: coach ?? night) else { return }
        try await health.writeSleepAnalysisIfNeeded(night: night)
    }

    private func recomputeAnalyses() {
        var output: [UUID: SleepAnalysisResult] = [:]
        for (index, night) in nights.enumerated() {
            let history = Array(nights.prefix(index))
            output[night.id] = analysisModel.analyze(night: night, history: history)
        }
        analyses = output
        if let last = nights.last, let analysis = output[last.id] {
            store.saveLastScore(analysis.score.total)
        }
    }

    private func publishWatchScore() {
        phoneConnectivity.updateApplicationContext(
            lastScore: lastAnalysis?.score.total,
            morning: lastNight?.morningDate
        )
    }

    private enum Keys {
        static let sampleData = "useSampleData"
        static let disclaimer = "disclaimerAccepted"
    }
}

struct TrendPoint: Identifiable {
    var date: Date
    var score: Int
    var asleepHours: Double
    var disturbanceIndex: Double
    var id: Date { date }
}
