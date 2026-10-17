import Foundation
import Testing
@testable import SleepCoachAnalysis

@Suite("Breathing disturbance heuristic")
struct BreathingDisturbanceHeuristicTests {
    let detector = BreathingDisturbanceHeuristic()
    let morning = NightBuilder.date(2026, 10, 17, 7, 0)

    @Test("Stable SpO2, RR and HR produce no dip flags")
    func cleanNightIsQuiet() {
        let night = SampleDataFactory.perfectNight(morning: morning)
        let events = detector.detect(in: night)
        let dips = events.filter { $0.kind == .possibleSpO2Dip || $0.kind == .combinedBreathingPattern }
        #expect(dips.isEmpty)
        #expect(!events.contains { $0.kind == .appleElevatedBreathingDisturbances })
    }

    @Test("Synthetic 4-point SpO2 dips are flagged with timestamps")
    func spo2DipsAreDetected() {
        var rng = SeededGenerator(seed: 42)
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.spo2Percent = SampleDataFactory.spo2WithDips(
            start: night.inBedStart,
            minutes: Int(night.inBedDuration / 60),
            dipCount: 8,
            rng: &rng
        )
        let events = detector.detectSpO2Dips(night)
        #expect(events.count >= 6)
        #expect(events.count <= 10)
        for event in events {
            #expect(event.kind == .possibleSpO2Dip)
            #expect(event.duration >= 10)
            #expect(event.timestamp >= night.inBedStart)
            #expect(event.timestamp <= night.inBedEnd)
            #expect(!SafetyCopy.containsBannedDiagnosisLanguage(event.explanation))
        }
    }

    @Test("Respiratory-rate spikes in a window flag irregularity")
    func respiratoryIrregularity() {
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.respiratoryRateBPM = NightBuilder.series(
            from: night.inBedStart,
            every: 60,
            count: 80
        ) { index, _ in
            index % 2 == 0 ? 8 : 22
        }
        let events = detector.detectRespiratoryIrregularity(night)
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.kind == .respiratoryIrregularity })
    }

    @Test("A 20 bpm HR swing after a dip becomes a combined event")
    func combinedPatternIsHigherSeverity() {
        var rng = SeededGenerator(seed: 7)
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.spo2Percent = SampleDataFactory.spo2WithDips(
            start: night.inBedStart,
            minutes: Int(night.inBedDuration / 60),
            dipCount: 3,
            rng: &rng
        )
        // Force a matching HR surge at the first dip.
        if let dipTime = detector.detectSpO2Dips(night).first?.timestamp {
            night.heartRateBPM = [
                TimedSample(date: dipTime.addingTimeInterval(-20), value: 52),
                TimedSample(date: dipTime.addingTimeInterval(10), value: 74),
                TimedSample(date: dipTime.addingTimeInterval(25), value: 70)
            ] + night.heartRateBPM
        }
        let events = detector.detect(in: night)
        #expect(events.contains { $0.kind == .combinedBreathingPattern && $0.severity == .high })
    }

    @Test("Apple elevated breathing disturbances is surfaced separately")
    func appleElevatedIsForwarded() {
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.appleBreathingDisturbances = AppleBreathingDisturbancesReading(
            date: morning,
            quantityValue: 1.8,
            classification: .elevated
        )
        let events = detector.detect(in: night)
        #expect(events.contains { $0.kind == .appleElevatedBreathingDisturbances })
        let apple = events.first { $0.kind == .appleElevatedBreathingDisturbances }
        #expect(apple?.explanation == SafetyCopy.appleElevatedAdvice)
    }

    @Test("No HealthKit vitals still returns an empty, safe result")
    func emptyVitals() {
        var night = SampleDataFactory.perfectNight(morning: morning)
        night.spo2Percent = []
        night.respiratoryRateBPM = []
        night.heartRateBPM = []
        night.appleBreathingDisturbances = nil
        #expect(detector.detect(in: night).isEmpty)
    }
}
