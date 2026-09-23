import MixerCore
import SwiftUI

struct AppVolumeRow: View {
    let item: MixerController.AppItem
    let icon: AppIcon
    let meter: MeterLevel
    let outputDevices: [AudioOutputDevice]
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onRoute: (String?) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VolumeControlRow(
                title: item.identity.displayName,
                volume: item.setting.volume,
                isMuted: item.setting.isMuted,
                isPlaying: item.isPlaying,
                meter: item.isProcessing ? meter : nil,
                subtitle: routeSubtitle,
                isSoloed: item.isSoloed,
                onToggleSolo: onToggleSolo,
                onVolumeChange: onVolumeChange,
                onToggleMute: onToggleMute
            ) {
                AppIconView(icon: icon)
            }
            .opacity(item.isSilencedBySolo ? 0.45 : 1)

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
            Menu("Play through") {
                Picker("Play through", selection: routeBinding) {
                    Text("System Output").tag(String?.none)
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Button(item.isSoloed ? "Stop Listening Alone" : "Listen to This App Alone", action: onToggleSolo)
            Divider()
            Button("Reset This App", action: onReset)
                .disabled(item.setting.isDefault)
        }
    }

    /// Shown only when the app is pinned somewhere other than the system output.
    private var routeSubtitle: RowSubtitle? {
        guard let name = item.routedDeviceName else { return nil }
        return item.isRouteUnavailable
            ? RowSubtitle(text: "→ \(name) (not connected)", isWarning: true)
            : RowSubtitle(text: "→ \(name)")
    }

    private var routeBinding: Binding<String?> {
        Binding(get: { item.setting.routeDeviceUID }, set: { onRoute($0) })
    }
}
