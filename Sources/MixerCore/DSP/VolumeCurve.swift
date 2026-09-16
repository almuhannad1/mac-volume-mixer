/// Maps the user-facing volume slider (0…1) to a linear amplitude gain.
///
/// A squared taper sounds far more even than a linear one: 50 % ≈ −12 dB, 10 % = −40 dB.
public enum VolumeCurve {
    public static func gain(forVolume volume: Double) -> Float {
        let clamped = Float(min(max(volume, 0), 1))
        return clamped * clamped
    }

    public static func gain(for setting: AppVolumeSetting) -> Float {
        setting.isMuted ? 0 : gain(forVolume: setting.volume)
    }
}
