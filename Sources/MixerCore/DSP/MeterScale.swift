import Foundation

/// Converts linear peak values into a 0…1 display level on a decibel scale.
public enum MeterScale {
    public static let floorDecibels: Float = -60

    public static func level(forPeak peak: Float) -> Float {
        guard peak.isFinite, peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        let normalized = (decibels - floorDecibels) / -floorDecibels
        return min(max(normalized, 0), 1)
    }

    /// Meter ballistics: jumps up instantly, falls back smoothly.
    public static func decayed(previous: Float, target: Float, releaseFactor: Float = 0.75) -> Float {
        let released = previous * releaseFactor
        let value = max(target, released)
        return value < 0.005 ? 0 : value
    }
}
