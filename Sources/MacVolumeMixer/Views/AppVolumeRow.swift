import SwiftUI

struct AppVolumeRow: View {
    let item: MixerController.AppItem
    let icon: AppIcon
    let meter: MeterLevel
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VolumeControlRow(
                title: item.identity.displayName,
                volume: item.setting.volume,
                isMuted: item.setting.isMuted,
                isPlaying: item.isPlaying,
                meter: item.isProcessing ? meter : nil,
                onVolumeChange: onVolumeChange,
                onToggleMute: onToggleMute
            ) {
                AppIconView(icon: icon)
            }

            if let failure = item.failureMessage {
                Label("Volume can't be applied to this app", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.leading, 38)
                    .help(failure)
            }
        }
        .help(item.identity.bundleIdentifier ?? item.identity.displayName)
        .contextMenu {
            Button("Reset to 100%", action: onReset)
                .disabled(item.setting.isDefault)
        }
    }
}
