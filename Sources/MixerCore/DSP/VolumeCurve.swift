/// Maps the user-facing volume slider (0…1) to a linear amplitude gain.
///
/// A squared taper sounds far more even than a linear one: 50 % ≈ −12 dB, 10 % = −40 dB.
public enum VolumeCurve {
    public static func gain(forVolume volume: Double) -> Float {
        let clamped = Float(min(max(volume, 0), 1))
        return clamped * clamped
    }

    public static func gain(for setting: EffectiveAppSetting) -> Float {
        setting.isMuted ? 0 : gain(forVolume: setting.volume)
    }

    /// Left/right gains for a setting, folding in its balance.
    ///
    /// Balance attenuates the opposite side rather than boosting one, so nothing ever clips.
    public static func channelGains(for setting: EffectiveAppSetting, scaledBy multiplier: Double = 1) -> ChannelGains {
        let base = gain(for: setting) * Float(min(max(multiplier, 0), 1))
        let balance = Float(min(max(setting.balance, -1), 1))
        return ChannelGains(
            left: balance <= 0 ? base : base * (1 - balance),
            right: balance >= 0 ? base : base * (1 + balance)
        )
    }
}
