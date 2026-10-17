import Foundation
import Testing
@testable import SleepCoachAnalysis

@Suite("Watch session draft")
struct SleepSessionDraftTests {
    @Test("Quiet motion infers a single asleep block")
    func quietNight() {
        let start = NightBuilder.date(2026, 10, 16, 23, 0)
        let motion = NightBuilder.motion(from: start, minutes: 60) { _ in 0.01 }
        let draft = SleepSessionDraft(
            start: start,
            end: start.addingTimeInterval(3600),
            motion: motion
        )
        let night = draft.asCoachNight(morning: NightBuilder.date(2026, 10, 17, 7, 0))
        #expect(night.provenance.motionSource == .aiSleepCoachSession)
        #expect(night.stages.contains { $0.stage.isAsleep })
        #expect(night.asleepDuration > 0)
    }

    @Test("Bursts of motion become awake intervals")
    func restlessBursts() {
        let start = NightBuilder.date(2026, 10, 16, 23, 0)
        let motion = NightBuilder.motion(from: start, minutes: 30) { index in
            index >= 10 && index < 15 ? 0.12 : 0.01
        }
        let draft = SleepSessionDraft(
            start: start,
            end: start.addingTimeInterval(30 * 60),
            motion: motion
        )
        let awake = draft.inferredStages().filter { $0.stage == .awake }
        #expect(!awake.isEmpty)
    }
}
