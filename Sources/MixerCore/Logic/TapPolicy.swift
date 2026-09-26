import Foundation

/// Decides when an app's audio must be routed through a process tap.
public enum TapPolicy {
    /// How long tap IO keeps running after an app goes quiet before it is stopped to save power.
    public static let ioIdleGrace: TimeInterval = 15
    /// How long a tap stays engaged after its setting returns to 100 % (avoids churn while dragging).
    public static let disengageDelay: TimeInterval = 2

    /// Apps at 100 %, unmuted and unrouted are never tapped: no latency, no CPU, no risk.
    /// Routing needs a tap even at unity gain, because the audio has to be re-rendered onto
    /// another device. Solo and call ducking need one too, to turn down apps the user has not
    /// configured themselves.
    /// Without capture authorization a muting tap would silence the app, so never engage then.
    public static func shouldEngage(
        setting: EffectiveAppSetting,
        captureAuthorized: Bool,
        isForcedByMixer: Bool = false
    ) -> Bool {
        captureAuthorized && (!setting.isDefault || isForcedByMixer)
    }

    public static func shouldRunIO(sessionID: String, activity: ActivityTracker, now: Date) -> Bool {
        activity.wasActive(sessionID, within: ioIdleGrace, now: now)
    }
}
