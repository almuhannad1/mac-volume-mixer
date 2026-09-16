/// The user's volume preference for one application.
public struct AppVolumeSetting: Codable, Hashable, Sendable {
    /// Slider position, always clamped to 0…1.
    public private(set) var volume: Double
    public var isMuted: Bool

    public static let `default` = AppVolumeSetting(volume: 1, isMuted: false)

    public init(volume: Double = 1, isMuted: Bool = false) {
        self.volume = Self.clamp(volume)
        self.isMuted = isMuted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        )
    }

    public mutating func setVolume(_ newValue: Double) {
        volume = Self.clamp(newValue)
    }

    /// `true` when the app would sound exactly as it does without the mixer.
    public var isDefault: Bool { !isMuted && volume >= 0.9995 }

    public var percent: Int { Int((volume * 100).rounded()) }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }
}
