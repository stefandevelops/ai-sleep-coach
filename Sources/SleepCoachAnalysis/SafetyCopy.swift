import Foundation

/// User-facing safety language. Keep medical claims out of insights and flags.
public enum SafetyCopy: Sendable {
    public static let productDisclaimer = """
    AI Sleep Coach is a personal wellness and portfolio app — not a medical device \
    and not a diagnostic tool. It does not detect, diagnose, treat or rule out sleep \
    apnoea or any other condition.

    Scores, insights and flagged events are on-device heuristics. They can be wrong. \
    A flag means the overnight signals looked unusual — never that sleep apnoea is present.

    For diagnosis, talk to a GP or sleep clinician. On Apple Watch Series 9 and later \
    (including Series 11), turn on Apple’s own Sleep Apnoea notifications in the \
    Health app (Browse → Respiratory). That is an Apple-regulated feature; this app is not.
    """

    public static let shortDisclaimer =
        "Not a medical device. Flags are possible disturbances, not a diagnosis."

    public static let breathingFlagTitle = "Possible breathing disturbances"

    public static let breathingFlagAdvice =
        "Possible breathing disturbances were flagged from overnight signals. This is not a diagnosis of sleep apnoea. Consider discussing the pattern with a doctor, and enable Apple’s Sleep Apnoea notifications in the Health app."

    public static let appleElevatedAdvice =
        "Apple Watch marked breathing disturbances as Elevated for this night. That is Apple’s own metric, not a diagnosis. Consider enabling Sleep Apnoea notifications in Health and talking with a GP if the pattern continues."

    public static let enableAppleSleepApnoeaHelp = """
    On iPhone: open Health → Browse → Respiratory → Sleep Apnoea Notifications → Set Up. \
    Wear Apple Watch to bed with Track Sleep with Apple Watch turned on. Apple needs \
    enough nights (typically 10 in 30 days) before it can notify you.
    """

    public static let bannedDiagnosisPhrases: [String] = [
        "you have sleep apnoea",
        "you have sleep apnea",
        "you have apnea",
        "you have apnoea",
        "diagnosed with sleep",
        "this confirms sleep apnoea",
        "this confirms sleep apnea",
        "you suffer from sleep apnoea",
        "you suffer from sleep apnea"
    ]

    public static func containsBannedDiagnosisLanguage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return bannedDiagnosisPhrases.contains { lowered.contains($0) }
    }

    public static func assertSafe(_ texts: [String]) -> Bool {
        texts.allSatisfy { !containsBannedDiagnosisLanguage($0) }
    }
}
