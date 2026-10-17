import Foundation

/// Seeded, reproducible nights for Simulator previews and tests.
public struct SampleDataFactory: Sendable {
    public var seed: UInt64

    public init(seed: UInt64 = 11) {
        self.seed = seed
    }

    public func lastNights(count: Int = 30, endingOn morning: Date = Date()) -> [SleepNight] {
        var rng = SeededGenerator(seed: seed)
        var nights: [SleepNight] = []
        let calendar = Calendar.current
        for offset in (0..<count).reversed() {
            guard let morningDate = calendar.date(byAdding: .day, value: -offset, to: morning) else {
                continue
            }
            let disturbed = offset == 0 || offset == 6 || offset == 13
            let short = offset == 3 || offset == 18
            nights.append(
                makeNight(
                    morning: morningDate,
                    disturbed: disturbed,
                    short: short,
                    restless: offset == 9,
                    rng: &rng
                )
            )
        }
        return nights
    }

    public func lastNight(endingOn morning: Date = Date()) -> SleepNight {
        lastNights(count: 1, endingOn: morning)[0]
    }

    public func makeNight(
        morning: Date,
        disturbed: Bool,
        short: Bool,
        restless: Bool,
        rng: inout SeededGenerator
    ) -> SleepNight {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let morningDay = calendar.startOfDay(for: morning)
        let bedtimeHour = 23
        let bedtimeMinute = Int(rng.nextInRange(10...40))
        let inBedStart = calendar.date(byAdding: .minute, value: bedtimeMinute, to:
            calendar.date(byAdding: .hour, value: bedtimeHour - 24, to: morningDay) ?? morning
        ) ?? morning.addingTimeInterval(-8 * 3600)

        let asleepHours = short ? rng.nextInRange(4.4...5.2) : rng.nextInRange(7.3...8.4)
        let extraAwake = restless ? 0.7 : 0.25
        let inBedHours = asleepHours + extraAwake
        let inBedEnd = inBedStart.addingTimeInterval(inBedHours * 3600)

        let deepShare = rng.nextInRange(0.14...0.20)
        let remShare = rng.nextInRange(0.18...0.24)
        let awakeShare = extraAwake / inBedHours
        let coreShare = max(0.35, 1 - deepShare - remShare - awakeShare)

        let total = inBedEnd.timeIntervalSince(inBedStart)
        let pattern: [(SleepStage, TimeInterval)] = [
            (.awake, total * 0.04),
            (.core, total * coreShare * 0.35),
            (.deep, total * deepShare * 0.55),
            (.core, total * coreShare * 0.20),
            (.rem, total * remShare * 0.40),
            (.awake, total * 0.03),
            (.core, total * coreShare * 0.25),
            (.deep, total * deepShare * 0.45),
            (.rem, total * remShare * 0.60),
            (.core, total * coreShare * 0.20),
            (.awake, total * max(0.01, awakeShare - 0.07))
        ]

        let stages = NightBuilder.stages(start: inBedStart, pattern: pattern, source: .sample)
        let minutes = Int(inBedHours * 60)

        let hr = NightBuilder.series(from: inBedStart, every: 60, count: minutes) { index, _ in
                let base = 56.0 + Double(rng.nextInRange(-3...3))
                let cycle = disturbed && index % 9 == 0 ? 16.0 : 0.0
                return base + cycle + sin(Double(index) / 18) * 2
        }
        let hrv = NightBuilder.series(from: inBedStart, every: 300, count: max(4, minutes / 5)) { _, _ in
            rng.nextInRange(38...70)
        }
        let spo2: [TimedSample]
        if disturbed {
            spo2 = Self.spo2WithDips(start: inBedStart, minutes: minutes, dipCount: 8, rng: &rng)
        } else {
            spo2 = NightBuilder.series(from: inBedStart, every: 30, count: minutes * 2) { _, _ in
                rng.nextInRange(95.5...98.2)
            }
        }
        let rr: [TimedSample]
        if disturbed {
            rr = NightBuilder.series(from: inBedStart, every: 60, count: minutes) { index, _ in
                let base = 14.5
                return index % 7 == 0 ? rng.nextInRange(7...22) : base + rng.nextInRange(-0.6...0.6)
            }
        } else {
            rr = NightBuilder.series(from: inBedStart, every: 60, count: minutes) { _, _ in
                rng.nextInRange(13.5...15.5)
            }
        }
        let motion = NightBuilder.motion(from: inBedStart, minutes: minutes) { index in
            if restless && index % 11 == 0 { return rng.nextInRange(0.06...0.14) }
            return rng.nextInRange(0.008...0.025)
        }
        let apple: AppleBreathingDisturbancesReading? = disturbed
            ? AppleBreathingDisturbancesReading(
                date: morningDay,
                quantityValue: 1.4,
                classification: .elevated
            )
            : AppleBreathingDisturbancesReading(
                date: morningDay,
                quantityValue: 0.2,
                classification: .notElevated
            )

        return SleepNight(
            morningDate: morningDay,
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            stages: stages,
            heartRateBPM: hr,
            hrvSDNN: hrv,
            spo2Percent: spo2,
            respiratoryRateBPM: rr,
            wristTemperatureDeltaC: TimedSample(date: morningDay, value: rng.nextInRange(-0.2...0.35)),
            motion: motion,
            appleBreathingDisturbances: apple,
            provenance: NightProvenance(
                sleepStagesSource: .sample,
                vitalsSource: .sample,
                motionSource: .sample
            ),
            isSampleData: true
        )
    }

    public static func spo2WithDips(
        start: Date,
        minutes: Int,
        dipCount: Int,
        rng: inout SeededGenerator
    ) -> [TimedSample] {
        let every: TimeInterval = 15
        let count = max(20, minutes * 4)
        var values = (0..<count).map { _ in rng.nextInRange(96.0...98.0) }
        let spacing = max(20, count / (dipCount + 1))
        if dipCount > 0 {
            for dip in 0..<dipCount {
                let centre = min(count - 6, spacing * (dip + 1))
                for j in 0..<5 {
                    let idx = centre + j
                    if idx < values.count {
                        values[idx] = 96.5 - 5.5 - Double(j == 2 ? 1 : 0)
                    }
                }
            }
        }
        return (0..<count).map { index in
            TimedSample(
                date: start.addingTimeInterval(Double(index) * every),
                value: values[index]
            )
        }
    }

    public static func perfectNight(morning: Date) -> SleepNight {
        let inBedStart = morning.addingTimeInterval(-8 * 3600 - 20 * 60.0)
        let inBedEnd = morning
        let pattern: [(SleepStage, TimeInterval)] = [
            (.awake, 10 * 60.0),
            (.core, 90 * 60.0),
            (.deep, 50 * 60.0),
            (.core, 40 * 60.0),
            (.rem, 35 * 60.0),
            (.awake, 8 * 60.0),
            (.core, 80 * 60.0),
            (.deep, 40 * 60.0),
            (.rem, 70 * 60.0),
            (.core, 55 * 60.0),
            (.awake, 12 * 60.0)
        ]
        let stages = NightBuilder.stages(start: inBedStart, pattern: pattern, source: .sample)
        let minutes = Int(inBedEnd.timeIntervalSince(inBedStart) / 60)
        return SleepNight(
            morningDate: morning,
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            stages: stages,
            heartRateBPM: NightBuilder.series(from: inBedStart, every: 60, count: minutes) { index, _ in
                62 - Double(index) / Double(max(minutes, 1)) * 7
            },
            hrvSDNN: NightBuilder.series(from: inBedStart, every: 300, count: minutes / 5) { _, _ in 55 },
            spo2Percent: NightBuilder.series(from: inBedStart, every: 30, count: minutes * 2) { _, _ in 97.2 },
            respiratoryRateBPM: NightBuilder.series(from: inBedStart, every: 60, count: minutes) { _, _ in 14.2 },
            wristTemperatureDeltaC: TimedSample(date: morning, value: 0.05),
            motion: NightBuilder.motion(from: inBedStart, minutes: minutes) { _ in 0.012 },
            appleBreathingDisturbances: AppleBreathingDisturbancesReading(
                date: morning,
                quantityValue: 0.1,
                classification: .notElevated
            ),
            provenance: NightProvenance(
                sleepStagesSource: .sample,
                vitalsSource: .sample,
                motionSource: .sample
            ),
            isSampleData: true
        )
    }

    public static func shortNight(morning: Date) -> SleepNight {
        var night = perfectNight(morning: morning)
        let inBedStart = morning.addingTimeInterval(-5 * 3600)
        night.inBedStart = inBedStart
        night.stages = NightBuilder.stages(
            start: inBedStart,
            pattern: [
                (.awake, 8 * 60.0),
                (.core, 90 * 60.0),
                (.deep, 40 * 60.0),
                (.rem, 35 * 60.0),
                (.core, 70 * 60.0),
                (.awake, 12 * 60.0)
            ],
            source: .sample
        )
        return night
    }
}

public struct SeededGenerator: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func nextInRange(_ range: ClosedRange<Double>) -> Double {
        let u = Double(next() % 10_000) / 10_000.0
        return range.lowerBound + (range.upperBound - range.lowerBound) * u
    }

    public mutating func nextInRange(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}
