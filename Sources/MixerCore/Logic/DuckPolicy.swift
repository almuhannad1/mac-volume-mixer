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
    ///
    /// Only apps that are **actually playing** and that the user can see are dimmed. Dimming
    /// anything else would engage a tap — and with it a realtime IO thread waking a hundred times
    /// a second — to turn down audio nobody is listening to.
    public static func levelMultiplier(for session: AudioAppSession, trigger: String?, level: Double) -> Double {
        guard session.identity.isUserFacing, session.isProducingOutput else { return 1 }
        return levelMultiplier(for: session.id, trigger: trigger, level: level)
    }

    /// Multiplier by session ID alone, without the "is it worth a tap?" test above.
    public static func levelMultiplier(for sessionID: String, trigger: String?, level: Double) -> Double {
        guard let trigger, trigger != sessionID else { return 1 }
        return min(max(level, 0), 1)
    }
}
