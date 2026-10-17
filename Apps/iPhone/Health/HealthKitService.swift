import Foundation
import HealthKit
import SleepCoachAnalysis

/// Reads Apple Watch sleep + vitals, and writes *our* sleep analysis only when
/// Apple did not already store a real night for the same window.
@MainActor
final class HealthKitService {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitServiceError.unavailable
        }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    func isAuthorized() async throws -> Bool {
        guard isHealthDataAvailable else { return false }
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let status = store.authorizationStatus(for: sleep)
        return status == .sharingAuthorized || status == .sharingDenied
            || status == .notDetermined
    }

    func loadRecentNights(days: Int) async throws -> [SleepNight] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end.addingTimeInterval(-Double(days) * 86400)
        let samples = try await categorySamples(type: .sleepAnalysis, start: start, end: end)
        let clusters = Self.cluster(samples)
        var nights: [SleepNight] = []
        for cluster in clusters {
            if let night = try await night(from: cluster) {
                nights.append(night)
            }
        }
        return nights.sorted { $0.morningDate < $1.morningDate }
    }

    func appleNight(on morning: Date) async throws -> SleepNight? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: morning)
        let windowStart = dayStart.addingTimeInterval(-16 * 3600)
        let windowEnd = dayStart.addingTimeInterval(14 * 3600)
        let samples = try await categorySamples(type: .sleepAnalysis, start: windowStart, end: windowEnd)
            .filter { Self.isAppleSource($0.sourceRevision.source) }
        let clusters = Self.cluster(samples)
        let match = clusters.max { a, b in
            asleepSeconds(a) < asleepSeconds(b)
        }
        guard let match, asleepSeconds(match) >= 30 * 60 else { return nil }
        return try await night(from: match)
    }

    func writeSleepAnalysisIfNeeded(night: SleepNight) async throws {
        let existing = try await categorySamples(
            type: .sleepAnalysis,
            start: night.inBedStart.addingTimeInterval(-30 * 60),
            end: night.inBedEnd.addingTimeInterval(30 * 60)
        )
        let appleAsleep = existing
            .filter { Self.isAppleSource($0.sourceRevision.source) }
            .filter { Self.stage(from: $0).isAsleep }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        if appleAsleep >= 2 * 3600 { return }

        let ours = existing.filter { Self.isOurSource($0.sourceRevision.source) }
        if ours.contains(where: { abs($0.startDate.timeIntervalSince(night.inBedStart)) < 120 }) {
            return
        }

        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var objects: [HKCategorySample] = [
            HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: night.inBedStart,
                end: night.inBedEnd,
                metadata: Self.coachMetadata
            )
        ]
        for interval in night.stages where interval.duration >= 60 {
            objects.append(
                HKCategorySample(
                    type: type,
                    value: Self.healthKitValue(for: interval.stage),
                    start: interval.start,
                    end: interval.end,
                    metadata: Self.coachMetadata
                )
            )
        }
        try await store.save(objects)
    }

    private func night(from samples: [HKCategorySample]) async throws -> SleepNight? {
        guard let first = samples.min(by: { $0.startDate < $1.startDate }),
              let last = samples.max(by: { $0.endDate < $1.endDate }) else { return nil }
        let inBedStart = first.startDate
        let inBedEnd = last.endDate
        guard inBedEnd.timeIntervalSince(inBedStart) >= 30 * 60 else { return nil }

        let appleSamples = samples.filter { Self.isAppleSource($0.sourceRevision.source) }
        let stageSource: DataSource = appleSamples.isEmpty ? .unknown : .appleWatch
        let stageSamples = appleSamples.isEmpty ? samples : appleSamples
        let stages = stageSamples.map {
            SleepStageInterval(
                start: $0.startDate,
                end: $0.endDate,
                stage: Self.stage(from: $0),
                source: Self.isAppleSource($0.sourceRevision.source) ? .appleWatch : .unknown
            )
        }

        async let hr = quantitySamples(.heartRate, start: inBedStart, end: inBedEnd, unit: Self.bpm)
        async let hrv = quantitySamples(.heartRateVariabilitySDNN, start: inBedStart, end: inBedEnd, unit: Self.ms)
        async let spo2 = quantitySamples(.oxygenSaturation, start: inBedStart, end: inBedEnd, unit: .percent())
        async let rr = quantitySamples(.respiratoryRate, start: inBedStart, end: inBedEnd, unit: Self.bpm)
        async let wrist = latestWristTemperature(start: inBedStart, end: inBedEnd.addingTimeInterval(12 * 3600))
        async let appleBD = latestBreathingDisturbances(start: inBedStart, end: inBedEnd.addingTimeInterval(12 * 3600))

        let spo2Percent = try await spo2.map {
            TimedSample(date: $0.date, value: $0.value <= 1.5 ? $0.value * 100 : $0.value)
        }

        return SleepNight(
            morningDate: Calendar.current.startOfDay(for: inBedEnd),
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            stages: stages,
            heartRateBPM: try await hr,
            hrvSDNN: try await hrv,
            spo2Percent: spo2Percent,
            respiratoryRateBPM: try await rr,
            wristTemperatureDeltaC: try await wrist,
            appleBreathingDisturbances: try await appleBD,
            provenance: NightProvenance(
                sleepStagesSource: stageSource,
                vitalsSource: .appleWatch,
                motionSource: .unknown
            )
        )
    }

    private func categorySamples(
        type identifier: HKCategoryTypeIdentifier,
        start: Date,
        end: Date
    ) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func quantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async throws -> [TimedSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let mapped = (samples as? [HKQuantitySample])?.map {
                    TimedSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private func latestWristTemperature(start: Date, end: Date) async throws -> TimedSample? {
        let samples = try await quantitySamples(
            .appleSleepingWristTemperature,
            start: start,
            end: end,
            unit: .degreeCelsius()
        )
        return samples.last
    }

    private func latestBreathingDisturbances(start: Date, end: Date) async throws -> AppleBreathingDisturbancesReading? {
        if #available(iOS 18.0, watchOS 11.0, *) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingBreathingDisturbances) else {
                return nil
            }
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                store.execute(query)
            }
            guard let sample = samples.last else { return nil }
            return AppleBreathingDisturbancesReading(
                date: sample.startDate,
                quantityValue: nil,
                classification: Self.classifyBreathingDisturbances(sample)
            )
        }
        return nil
    }

    @available(iOS 18.0, watchOS 11.0, *)
    private static func classifyBreathingDisturbances(_ sample: HKQuantitySample) -> AppleBreathingDisturbancesClassification {
        guard let classified = HKAppleSleepingBreathingDisturbancesClassification(classifying: sample.quantity) else {
            return .unknown
        }
        switch classified {
        case .elevated: return .elevated
        case .notElevated: return .notElevated
        @unknown default: return .unknown
        }
    }

    private static func cluster(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var clusters: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        for sample in sorted {
            if let last = current.last, sample.startDate.timeIntervalSince(last.endDate) > 4 * 3600 {
                clusters.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    private func asleepSeconds(_ samples: [HKCategorySample]) -> TimeInterval {
        samples
            .filter { Self.stage(from: $0).isAsleep }
            .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
    }

    static func isAppleSource(_ source: HKSource) -> Bool {
        let bundle = source.bundleIdentifier.lowercased()
        let name = source.name.lowercased()
        if bundle.contains("aisleepcoach") || bundle.contains("stefandevelops") { return false }
        return bundle.hasPrefix("com.apple") || name.contains("apple") || name.contains("watch")
    }

    static func isOurSource(_ source: HKSource) -> Bool {
        let bundle = source.bundleIdentifier.lowercased()
        return bundle.contains("aisleepcoach") || bundle.contains("stefandevelops")
    }

    static func stage(from sample: HKCategorySample) -> SleepStage {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .asleepUnspecified
        default: return .asleepUnspecified
        }
    }

    static func healthKitValue(for stage: SleepStage) -> Int {
        switch stage {
        case .inBed: return HKCategoryValueSleepAnalysis.inBed.rawValue
        case .awake: return HKCategoryValueSleepAnalysis.awake.rawValue
        case .core: return HKCategoryValueSleepAnalysis.asleepCore.rawValue
        case .deep: return HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        case .rem: return HKCategoryValueSleepAnalysis.asleepREM.rawValue
        case .asleepUnspecified: return HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        }
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private static let ms = HKUnit.secondUnit(with: .milli)
    private static let coachMetadata: [String: Any] = [
        "AISleepCoachSource": "companion-session"
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
        ]
        if #available(iOS 18.0, watchOS 11.0, *) {
            if let breathing = HKQuantityType.quantityType(forIdentifier: .appleSleepingBreathingDisturbances) {
                types.insert(breathing)
            }
        }
        return types
    }

    static var writeTypes: Set<HKSampleType> {
        [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
    }
}

enum HealthKitServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is not available on this device."
        }
    }
}
