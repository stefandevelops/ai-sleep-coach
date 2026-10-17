import Foundation
import Testing
@testable import SleepCoachAnalysis

@Suite("Sleep score engine")
struct SleepScoreEngineTests {
    let engine = SleepScoreEngine()
    let morning = NightBuilder.date(2026, 10, 17, 7, 0)

    @Test("A textbook 8-hour night scores in the high band")
    func perfectNightIsHigh() {
        let night = SampleDataFactory.perfectNight(morning: morning)
        let score = engine.score(night: night, history: [])
        #expect(score.total >= 85)
        #expect(score.duration >= 90)
        #expect(score.total <= 100)
        #expect(night.asleepDuration / 3600 >= 7)
        #expect(night.hasDetailedStages)
    }

    @Test("A 4–5 hour night is penalised on duration and total")
    func shortNightPenalised() {
        let night = SampleDataFactory.shortNight(morning: morning)
        let score = engine.score(night: night, history: [])
        #expect(score.duration < 40)
        #expect(score.total < 75)
        #expect(score.total < engine.score(night: SampleDataFactory.perfectNight(morning: morning), history: []).total)
    }

    @Test("Missing optional vitals still produces a score")
    func missingVitalsNeutralRecovery() {
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.heartRateBPM = []
        night.hrvSDNN = []
        night.spo2Percent = []
        night.respiratoryRateBPM = []
        night.wristTemperatureDeltaC = nil
        let score = engine.score(night: night, history: [])
        #expect(score.total >= 50)
        #expect(score.recovery == 70)
    }

    @Test("Unspecified stages do not collapse the stage component to zero")
    func unspecifiedStagesAreConservative() {
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.stages = NightBuilder.stages(
            start: night.inBedStart,
            pattern: [(.asleepUnspecified, 8 * 3600.0), (.awake, 15 * 60.0)],
            source: .aiSleepCoachSession
        )
        let score = engine.score(night: night, history: [])
        #expect(score.stages >= 50)
        #expect(score.stages < 90)
    }

    @Test("Scattered bedtimes lower consistency versus a regular week")
    func consistencyUsesHistory() {
        let regular = (0..<6).map { offset -> SleepNight in
            var night = SampleDataFactory.perfectNight(morning: morning.addingTimeInterval(Double(-offset) * 86400))
            night.inBedStart = NightBuilder.date(2026, 10, 16 - offset, 23, 15)
            return night
        }
        var tonight = SampleDataFactory.perfectNight(morning: morning)
        tonight.inBedStart = NightBuilder.date(2026, 10, 16, 23, 18)
        let steady = engine.consistencyScore(night: tonight, history: regular)

        var wild = tonight
        wild.inBedStart = NightBuilder.date(2026, 10, 16, 2, 40)
        let chaoticHistory = regular.enumerated().map { index, night -> SleepNight in
            var copy = night
            copy.inBedStart = NightBuilder.date(2026, 10, 16 - index, index % 2 == 0 ? 21 : 2, 10 + index * 7)
            return copy
        }
        let scattered = engine.consistencyScore(night: wild, history: chaoticHistory)
        #expect(steady > scattered)
        #expect(steady >= 80)
    }

    @Test("Weighted total is a rounded combination of components")
    func weightedTotal() {
        let night = SampleDataFactory.perfectNight(morning: morning)
        let score = engine.score(night: night, history: [])
        let w = score.weights
        let expected =
            (score.duration * w.duration
                + score.consistency * w.consistency
                + score.stages * w.stages
                + score.restlessness * w.restlessness
                + score.recovery * w.recovery) / w.total
        #expect(abs(Double(score.total) - expected) < 1.1)
    }
}
