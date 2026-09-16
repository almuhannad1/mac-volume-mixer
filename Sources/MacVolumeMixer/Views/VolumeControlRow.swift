import MixerCore
import SwiftUI

/// Icon, title, percentage, mute button, slider and optional level meter.
/// Shared by the master volume and every application row.
struct VolumeControlRow<Leading: View>: View {
    let title: String
    let volume: Double
    let isMuted: Bool
    var isEnabled = true
    var canMute = true
    var isPlaying = false
    var meter: MeterLevel?
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    @ViewBuilder let leading: () -> Leading

    private var percent: Int { Int((volume * 100).rounded()) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leading()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                header
                controls
                if let meter {
                    ActivityMeterView(level: meter)
                        .padding(.leading, 26)
                        .padding(.top, 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tint)
                    .help("Playing audio")
                    .accessibilityLabel("Playing audio")
            }
            Spacer(minLength: 8)
            Text(isEnabled ? "\(percent)%" : "—")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(isMuted ? .tertiary : .secondary)
                .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: onToggleMute) {
                Image(systemName: VolumeGlyph.speakerSymbol(volume: volume, isMuted: isMuted))
                    .font(.system(size: 12))
                    .foregroundStyle(isMuted ? Color.red.opacity(0.85) : Color.secondary)
                    .frame(width: 20, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .disabled(!canMute || !isEnabled)
            .help(isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(isMuted ? "Unmute \(title)" : "Mute \(title)")

            Slider(value: Binding(get: { volume }, set: { onVolumeChange($0) }), in: 0...1)
                .controlSize(.small)
                .disabled(!isEnabled)
                .opacity(isMuted ? 0.55 : 1)
                .accessibilityLabel("\(title) volume")
                .accessibilityValue(isMuted ? "Muted, \(percent) percent" : "\(percent) percent")
        }
    }
}
