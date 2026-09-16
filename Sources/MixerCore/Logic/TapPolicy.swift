import Foundation

/// Decides when an app's audio must be routed through a process tap.
public enum TapPolicy {
    /// How long tap IO keeps running after an app goes quiet before it is stopped to save power.
    public static let ioIdleGrace: TimeInterval = 15
    /// How long a tap stays engaged after its setting returns to 100 % (avoids churn while dragging).
    public static let disengageDelay: TimeInterval = 2

    /// Apps at 100 % and unmuted are never tapped: no latency, no CPU, no risk.
    /// Without capture authorization a muting tap would silence the app, so never engage then.
    public static func shouldEngage(setting: AppVolumeSetting, captureAuthorized: Bool) -> Bool {
        captureAuthorized && !setting.isDefault
    }

    public static func shouldRunIO(sessionID: String, activity: ActivityTracker, now: Date) -> Bool {
        activity.wasActive(sessionID, within: ioIdleGrace, now: now)
    }
}
