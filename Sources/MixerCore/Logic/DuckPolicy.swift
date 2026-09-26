import Foundation

/// Decides when to dim everything else because a call is in progress.
///
/// A call is detected by an app holding the microphone open
/// (`kAudioProcessPropertyIsRunningInput`). Only user-facing apps count: macOS keeps services
/// such as Siri's speech recogniser listening more or less permanently, and letting those trigger
/// ducking would leave the Mac quiet forever.
public enum DuckPolicy {
    /// Others drop to this fraction of their own level while a call is active.
    public static let defaultLevel: Double = 0.3
    /// How long the dip takes, so it sounds deliberate instead of like a glitch.
    public static let glide: TimeInterval = 0.25

    /// The app whose call should dim the others, or `nil` when no call is in progress.
    public static func duckTrigger(in sessions: [AudioAppSession]) -> String? {
        sessions.first { $0.isUsingInput && $0.identity.isUserFacing }?.id
    }

    /// Multiplier for one app's gain: the app on the call keeps its own level, the rest dip.
    public static func levelMultiplier(for sessionID: String, trigger: String?, level: Double) -> Double {
        guard let trigger, trigger != sessionID else { return 1 }
        return min(max(level, 0), 1)
    }
}
