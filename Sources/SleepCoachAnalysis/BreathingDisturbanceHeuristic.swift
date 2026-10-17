import Foundation

public struct BreathingDetectorConfiguration: Codable, Sendable, Equatable {
    public var spo2DipDropPercent: Double
    public var spo2MinDuration: TimeInterval
    public var spo2MaxDuration: TimeInterval
    public var spo2BaselineWindow: TimeInterval
    public var maxGapInsideEvent: TimeInterval
    public var hrSurgeBPM: Double
    public var hrSurgeLookahead: TimeInterval
    public var rrWindow: TimeInterval
    public var rrCVThreshold: Double
    public var combineWindow: TimeInterval

    public static let `default` = BreathingDetectorConfiguration(
        spo2DipDropPercent: 4.0,
        spo2MinDuration: 10,
        spo2MaxDuration: 150,
        spo2BaselineWindow: 5 * 60.0,
        maxGapInsideEvent: 30,
        hrSurgeBPM: 10,
        hrSurgeLookahead: 45,
        rrWindow: 10 * 60.0,
        rrCVThreshold: 0.18,
        combineWindow: 60
    )

    public init(
        spo2DipDropPercent: Double,
        spo2MinDuration: TimeInterval,
        spo2MaxDuration: TimeInterval,
        spo2BaselineWindow: TimeInterval,
        maxGapInsideEvent: TimeInterval,
        hrSurgeBPM: Double,
        hrSurgeLookahead: TimeInterval,
        rrWindow: TimeInterval,
        rrCVThreshold: Double,
        combineWindow: TimeInterval
    ) {
        self.spo2DipDropPercent = spo2DipDropPercent
        self.spo2MinDuration = spo2MinDuration
        self.spo2MaxDuration = spo2MaxDuration
        self.spo2BaselineWindow = spo2BaselineWindow
        self.maxGapInsideEvent = maxGapInsideEvent
        self.hrSurgeBPM = hrSurgeBPM
        self.hrSurgeLookahead = hrSurgeLookahead
        self.rrWindow = rrWindow
        self.rrCVThreshold = rrCVThreshold
        self.combineWindow = combineWindow
    }
}

/// Transparent statistical detector. Every threshold is in
/// `BreathingDetectorConfiguration` so tests can lock behaviour and a later
/// Core ML classifier can replace this type behind `BreathingDisturbanceDetector`.
public struct BreathingDisturbanceHeuristic: BreathingDisturbanceDetector {
    public var configuration: BreathingDetectorConfiguration

    public init(configuration: BreathingDetectorConfiguration = .default) {
        self.configuration = configuration
    }

    public func detect(in night: SleepNight) -> [FlaggedEvent] {
        var events: [FlaggedEvent] = []
        events += detectSpO2Dips(night)
        events += detectRespiratoryIrregularity(night)
        events += detectHeartRateCycles(night)
        events = mergeCombinedEvents(events)
        if let apple = night.appleBreathingDisturbances,
           apple.classification == .elevated {
            events.append(
                FlaggedEvent(
                    timestamp: apple.date,
                    duration: night.inBedDuration,
                    kind: .appleElevatedBreathingDisturbances,
                    severity: .moderate,
                    explanation: SafetyCopy.appleElevatedAdvice,
                    supportingSignals: ["appleBreathingDisturbances=elevated"]
                )
            )
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    public func detectSpO2Dips(_ night: SleepNight) -> [FlaggedEvent] {
        let samples = night.spo2Percent.sorted { $0.date < $1.date }
        guard samples.count >= 8 else { return [] }
        var dipPoints: [TimedSample] = []
        for (index, sample) in samples.enumerated() {
            let windowStart = sample.date.addingTimeInterval(-configuration.spo2BaselineWindow)
            let baselineSamples = samples[0...index]
                .filter { $0.date >= windowStart }
                .map(\.value)
            guard let baseline = Statistics.median(baselineSamples) else { continue }
            if sample.value <= baseline - configuration.spo2DipDropPercent {
                dipPoints.append(sample)
            }
        }
        let groups = groupConsecutive(dipPoints, maxGap: configuration.maxGapInsideEvent)
        return groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            let duration = max(1, last.date.timeIntervalSince(first.date))
            guard duration >= configuration.spo2MinDuration,
                  duration <= configuration.spo2MaxDuration else { return nil }
            let minSpO2 = group.map(\.value).min() ?? first.value
            var signals = ["spo2Min=\(String(format: "%.1f", minSpO2))%"]
            var severity: FlagSeverity = minSpO2 <= 88 ? .high : (duration >= 30 ? .moderate : .low)
            if heartRateSurged(around: first.date, in: night) {
                signals.append("hrSurge")
                if severity < .moderate { severity = .moderate }
            }
            return FlaggedEvent(
                timestamp: first.date,
                duration: duration,
                kind: .possibleSpO2Dip,
                severity: severity,
                explanation: "A drop in blood oxygen of at least \(Int(configuration.spo2DipDropPercent)) percentage points lasted \(Int(duration.rounded()))s. This can have many causes and is not a diagnosis. \(SafetyCopy.shortDisclaimer)",
                supportingSignals: signals
            )
        }
    }

    public func detectRespiratoryIrregularity(_ night: SleepNight) -> [FlaggedEvent] {
        let samples = night.respiratoryRateBPM.sorted { $0.date < $1.date }
        guard samples.count >= 6 else { return [] }
        var events: [FlaggedEvent] = []
        var cursor = samples.first?.date ?? night.inBedStart
        let end = samples.last?.date ?? night.inBedEnd
        while cursor < end {
            let windowEnd = cursor.addingTimeInterval(configuration.rrWindow)
            let window = samples.filter { $0.date >= cursor && $0.date < windowEnd }.map(\.value)
            if window.count >= 4,
               let mean = Statistics.mean(window),
               mean >= 6, mean <= 28,
               let cv = Statistics.coefficientOfVariation(window),
               cv >= configuration.rrCVThreshold {
                events.append(
                    FlaggedEvent(
                        timestamp: cursor,
                        duration: configuration.rrWindow,
                        kind: .respiratoryIrregularity,
                        severity: cv >= 0.28 ? .moderate : .low,
                        explanation: "Respiratory rate looked irregular in this stretch (variation \(Int((cv * 100).rounded()))% of the average). Irregularity has many causes, including movement. \(SafetyCopy.shortDisclaimer)",
                        supportingSignals: ["rrCV=\(String(format: "%.2f", cv))", "rrMean=\(String(format: "%.1f", mean))"]
                    )
                )
            }
            cursor = cursor.addingTimeInterval(configuration.rrWindow / 2)
        }
        return events
    }

    public func detectHeartRateCycles(_ night: SleepNight) -> [FlaggedEvent] {
        let samples = night.heartRateBPM.sorted { $0.date < $1.date }
        guard samples.count >= 12 else { return [] }
        var events: [FlaggedEvent] = []
        // Look for bradycardia-then-tachycardia swings over ~60–90s, a non-specific pattern.
        for i in 0..<(samples.count - 4) {
            let a = samples[i]
            let window = samples.filter {
                $0.date >= a.date && $0.date <= a.date.addingTimeInterval(90)
            }
            guard window.count >= 4,
                  let minHR = window.map(\.value).min(),
                  let maxHR = window.map(\.value).max() else { continue }
            let swing = maxHR - minHR
            if swing >= 18,
               let minSample = window.first(where: { $0.value == minHR }),
               let maxSample = window.first(where: { $0.value == maxHR }),
               maxSample.date > minSample.date {
                events.append(
                    FlaggedEvent(
                        timestamp: minSample.date,
                        duration: maxSample.date.timeIntervalSince(minSample.date),
                        kind: .heartRatePattern,
                        severity: swing >= 28 ? .moderate : .low,
                        explanation: "Heart rate rose by \(Int(swing.rounded())) bpm shortly after a dip. That pattern is non-specific. \(SafetyCopy.shortDisclaimer)",
                        supportingSignals: ["hrSwing=\(Int(swing.rounded()))"]
                    )
                )
            }
        }
        return collapseNearby(events, window: 120)
    }

    private func mergeCombinedEvents(_ events: [FlaggedEvent]) -> [FlaggedEvent] {
        let dips = events.filter { $0.kind == .possibleSpO2Dip }
        let others = events.filter { $0.kind == .respiratoryIrregularity || $0.kind == .heartRatePattern }
        var combinedIDs: Set<UUID> = []
        var extra: [FlaggedEvent] = []
        for dip in dips {
            let nearby = others.filter {
                abs($0.timestamp.timeIntervalSince(dip.timestamp)) <= configuration.combineWindow
            }
            if !nearby.isEmpty {
                nearby.forEach { combinedIDs.insert($0.id) }
                combinedIDs.insert(dip.id)
                extra.append(
                    FlaggedEvent(
                        timestamp: dip.timestamp,
                        duration: dip.duration,
                        kind: .combinedBreathingPattern,
                        severity: .high,
                        explanation: SafetyCopy.breathingFlagAdvice,
                        supportingSignals: [dip.kind.rawValue] + nearby.map(\.kind.rawValue)
                    )
                )
            }
        }
        let remaining = events.filter { !combinedIDs.contains($0.id) }
        return remaining + extra
    }

    private func heartRateSurged(around date: Date, in night: SleepNight) -> Bool {
        let samples = night.heartRateBPM
        let before = samples.filter {
            $0.date >= date.addingTimeInterval(-30) && $0.date <= date
        }.map(\.value)
        let after = samples.filter {
            $0.date >= date && $0.date <= date.addingTimeInterval(configuration.hrSurgeLookahead)
        }.map(\.value)
        guard let minBefore = before.min() ?? samples.filter({ $0.date <= date }).map(\.value).min(),
              let maxAfter = after.max() else { return false }
        return maxAfter - minBefore >= configuration.hrSurgeBPM
    }

    private func groupConsecutive(_ samples: [TimedSample], maxGap: TimeInterval) -> [[TimedSample]] {
        guard !samples.isEmpty else { return [] }
        var groups: [[TimedSample]] = []
        var current: [TimedSample] = [samples[0]]
        for sample in samples.dropFirst() {
            if let last = current.last, sample.date.timeIntervalSince(last.date) <= maxGap {
                current.append(sample)
            } else {
                groups.append(current)
                current = [sample]
            }
        }
        groups.append(current)
        return groups
    }

    private func collapseNearby(_ events: [FlaggedEvent], window: TimeInterval) -> [FlaggedEvent] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var result: [FlaggedEvent] = []
        for event in sorted {
            if let last = result.last, event.timestamp.timeIntervalSince(last.timestamp) < window {
                continue
            }
            result.append(event)
        }
        return result
    }
}
