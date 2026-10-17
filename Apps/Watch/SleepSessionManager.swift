import CoreMotion
import Foundation
import SleepCoachAnalysis
import WatchConnectivity
import WatchKit

/// Overnight session using `WKExtendedRuntimeSession` sleep tracking (the
/// supported way to keep a Watch app alive in bed). Motion is sampled locally;
/// heart rate / SpO₂ / stages continue to be written by watchOS into HealthKit
/// and are read on iPhone. An `HKWorkoutSession` is not used — it would show
/// up as a workout in Fitness.
@MainActor
final class SleepSessionManager: NSObject, WKExtendedRuntimeSessionDelegate, WCSessionDelegate {
    var onStateChange: ((Bool, Date?) -> Void)?
    var onScore: ((Int) -> Void)?

    private var runtime: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var minuteBuckets: [Date: (max: Double, active: Int)] = [:]
    private var startedAt: Date?
    private var wcSession: WCSession?

    func activate() {
        motionQueue.maxConcurrentOperationCount = 1
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
        Task { await WatchHealthAuth.request() }
    }

    func start() {
        guard runtime == nil else { return }
        minuteBuckets = [:]
        startedAt = Date()
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        runtime = session
        session.start()
        startMotion()
        onStateChange?(true, startedAt)
        WKInterfaceDevice.current().play(.start)
    }

    func stop() {
        guard startedAt != nil else { return }
        stopMotion()
        let session = runtime
        runtime = nil
        finishAndSend()
        session?.invalidate()
        WKInterfaceDevice.current().play(.stop)
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            stop()
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith error: (any Error)?
    ) {
        Task { @MainActor in
            guard startedAt != nil else { return }
            stopMotion()
            finishAndSend()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let score = applicationContext["lastScore"] as? Int {
            Task { @MainActor in onScore?(score) }
        }
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let data else { return }
            let mag = sqrt(
                data.acceleration.x * data.acceleration.x
                    + data.acceleration.y * data.acceleration.y
                    + data.acceleration.z * data.acceleration.z
            )
            let dynamic = abs(mag - 1.0)
            let now = Date()
            Task { @MainActor in
                self?.record(dynamic: dynamic, at: now)
            }
        }
    }

    private func stopMotion() {
        motion.stopAccelerometerUpdates()
    }

    private func record(dynamic: Double, at date: Date) {
        let minute = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
        var bucket = minuteBuckets[minute] ?? (max: 0, active: 0)
        bucket.max = max(bucket.max, dynamic)
        if dynamic >= 0.03 { bucket.active += 1 }
        minuteBuckets[minute] = bucket
    }

    private func finishAndSend() {
        let end = Date()
        let start = startedAt ?? end.addingTimeInterval(-60)
        startedAt = nil
        runtime = nil
        onStateChange?(false, nil)
        let motionSamples: [MotionSample] = minuteBuckets.keys.sorted().map { minute in
            let bucket = minuteBuckets[minute]!
            return MotionSample(
                date: minute,
                magnitude: bucket.max,
                activeSeconds: min(60, bucket.active / 10)
            )
        }
        let draft = SleepSessionDraft(start: start, end: end, motion: motionSamples)
        send(draft)
    }

    private func send(_ draft: SleepSessionDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        if let session = wcSession, session.isReachable {
            session.sendMessage(["draft": data], replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(["draft": data])
            })
        } else {
            wcSession?.transferUserInfo(["draft": data])
        }
    }
}
