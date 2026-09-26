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
    let onBalance: (Double) -> Void
    let onMono: (Bool) -> Void
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
            .opacity(item.isSilencedBySolo ? 0.45 : (item.isDuckedByCall ? 0.7 : 1))

            if item.isDuckedByCall, item.failureMessage == nil {
                Label("Dimmed for a call", systemImage: "phone.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 38)
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
            Menu("Balance") {
                Picker("Balance", selection: balanceBinding) {
                    Text("Left").tag(-1.0)
                    Text("Center Left").tag(-0.5)
                    Text("Center").tag(0.0)
                    Text("Center Right").tag(0.5)
                    Text("Right").tag(1.0)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Toggle("Mono", isOn: Binding(get: { item.setting.isMono }, set: { onMono($0) }))
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

    /// Snaps to the nearest of the five presets the menu offers.
    private var balanceBinding: Binding<Double> {
        Binding(
            get: { (item.setting.balance * 2).rounded() / 2 },
            set: { onBalance($0) }
        )
    }

    private var routeBinding: Binding<String?> {
        Binding(get: { item.setting.routeDeviceUID }, set: { onRoute($0) })
    }
}
