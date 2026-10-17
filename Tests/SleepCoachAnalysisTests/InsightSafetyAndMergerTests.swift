import Foundation
import Testing
@testable import SleepCoachAnalysis

@Suite("Insights, safety copy, merger, features")
struct InsightSafetyAndMergerTests {
    let model = HeuristicSleepAnalysisModel()
    let morning = NightBuilder.date(2026, 10, 17, 7, 0)

    @Test("End-to-end analysis never uses diagnosis language")
    func noDiagnosisLanguage() {
        let factory = SampleDataFactory(seed: 11)
        let nights = (0..<8).map { offset in
            factory.lastNights(count: 1, endingOn: morning.addingTimeInterval(Double(-offset) * 86_400))[0]
        }
        let history = Array(nights.dropFirst())
        let result = model.analyze(night: nights[0], history: history)
        let texts = result.insights.map { $0.title + " " + $0.body }
            + result.flaggedEvents.map(\.explanation)
            + [SafetyCopy.breathingFlagAdvice, SafetyCopy.shortDisclaimer]
        #expect(SafetyCopy.assertSafe(texts))
        #expect(result.score.total >= 0 && result.score.total <= 100)
        #expect(result.featureVector["asleepHours"] != nil)
    }

    @Test("Short-sleep insights mention duration")
    func shortSleepInsight() {
        let night = SampleDataFactory.shortNight(morning: morning)
        let result = model.analyze(night: night, history: [])
        #expect(result.insights.contains { $0.category == .duration && $0.body.lowercased().contains("short") })
    }

    @Test("Apple stages covering the night block a duplicate HealthKit write")
    func mergerPrefersAppleAndBlocksWrite() {
        let apple = SampleDataFactory.perfectNight(morning: morning)
        var coach = apple
        coach.stages = NightBuilder.stages(
            start: apple.inBedStart,
            pattern: [(.asleepUnspecified, 8 * 3600.0)],
            source: .aiSleepCoachSession
        )
        coach.motion = NightBuilder.motion(from: apple.inBedStart, minutes: 20) { _ in 0.08 }
        coach.provenance = NightProvenance(
            sleepStagesSource: .aiSleepCoachSession,
            vitalsSource: .aiSleepCoachSession,
            motionSource: .aiSleepCoachSession
        )

        let merger = SleepNightMerger()
        #expect(merger.appleStagesAreAuthoritative(apple))
        #expect(merger.shouldWriteCoachSleepAnalysis(apple: apple, coach: coach) == false)
        #expect(merger.shouldWriteCoachSleepAnalysis(apple: nil, coach: coach) == true)

        let merged = merger.merge(apple: apple, coach: coach)
        #expect(merged?.provenance.sleepStagesSource == .appleWatch)
        #expect(merged?.hasDetailedStages == true)
        #expect(merged?.motion.isEmpty == false)
    }

    @Test("Coach stages are used when Apple has almost no sleep")
    func mergerFallsBackToCoach() {
        var apple = SampleDataFactory.perfectNight(morning: morning)
        apple.stages = NightBuilder.stages(
            start: apple.inBedStart,
            pattern: [(.awake, 20 * 60.0)],
            source: .appleWatch
        )
        let coach = SampleDataFactory.perfectNight(morning: morning)
        let merger = SleepNightMerger()
        #expect(merger.shouldWriteCoachSleepAnalysis(apple: apple, coach: coach))
        let merged = merger.merge(apple: apple, coach: coach)
        #expect(merged?.provenance.sleepStagesSource != .appleWatch)
        #expect(merged?.asleepDuration ?? 0 > 3600)
    }

    @Test("Feature vector keys are stable for a future Core ML swap")
    func featureKeys() {
        let night = SampleDataFactory.perfectNight(morning: morning)
        let vector = HeuristicFeatureExtractor().features(from: night, history: [])
        for key in ["asleepHours", "efficiency", "deepPercent", "remPercent", "meanHeartRate", "minSpO2", "rrCV"] {
            #expect(vector[key] != nil, "missing \(key)")
        }
        #expect(UnavailabilityCoreMLSleepModel().isAvailable == false)
    }

    @Test("Banned-phrase helper catches the obvious diagnosis sentences")
    func bannedHelper() {
        #expect(SafetyCopy.containsBannedDiagnosisLanguage("You have sleep apnoea"))
        #expect(SafetyCopy.containsBannedDiagnosisLanguage("You have sleep apnea."))
        #expect(!SafetyCopy.containsBannedDiagnosisLanguage(SafetyCopy.breathingFlagAdvice))
    }

    @Test("Seeded sample months are reproducible")
    func sampleDataIsDeterministic() {
        let a = SampleDataFactory(seed: 11).lastNights(count: 30, endingOn: morning)
        let b = SampleDataFactory(seed: 11).lastNights(count: 30, endingOn: morning)
        #expect(a.count == 30)
        #expect(a.map(\.inBedStart) == b.map(\.inBedStart))
        #expect(a[0].isSampleData)
    }
}
