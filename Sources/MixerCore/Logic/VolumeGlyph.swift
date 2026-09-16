/// SF Symbol names for volume states.
public enum VolumeGlyph {
    public static func speakerSymbol(volume: Double, isMuted: Bool) -> String {
        if isMuted || volume <= 0.0005 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
