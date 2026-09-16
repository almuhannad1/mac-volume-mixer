import SwiftUI

struct PermissionBannerView: View {
    let notice: MixerViewModel.CaptureNotice
    let onOpenSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title).font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(.orange)
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case let .permissionNeeded(isChecking) = notice {
                HStack(spacing: 8) {
                    Button("Open System Settings", action: onOpenSettings)
                    Button("Check Again", action: onRetry).disabled(isChecking)
                    if isChecking {
                        ProgressView().controlSize(.mini)
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch notice {
        case .permissionNeeded: "Allow System Audio Recording"
        case .unavailable: "Per-app volume unavailable"
        case .processingDisabled: "Per-app volume disabled"
        }
    }

    private var symbol: String {
        switch notice {
        case .permissionNeeded: "lock.shield"
        case .unavailable, .processingDisabled: "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch notice {
        case .permissionNeeded:
            "To change an app's volume, Mac Volume Mixer must capture that app's audio. Enable it under "
                + "Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. "
                + "Master volume and output switching work without it."
        case let .unavailable(reason):
            reason
        case .processingDisabled:
            "Launched with --disable-taps. App volumes are remembered but not applied."
        }
    }
}
