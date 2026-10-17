import HealthKit

enum WatchHealthAuth {
    static func request() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        var read: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        ]
        if #available(watchOS 11.0, *) {
            if let breathing = HKQuantityType.quantityType(forIdentifier: .appleSleepingBreathingDisturbances) {
                read.insert(breathing)
            }
            if let wrist = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                read.insert(wrist)
            }
        }
        let write: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        try? await store.requestAuthorization(toShare: write, read: read)
    }
}
