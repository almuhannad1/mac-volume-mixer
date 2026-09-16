import AppKit
import AudioHAL
import SwiftUI

struct AudioSettingsView: View {
    @Bindable var preferences: AppPreferences
    let controller: MixerController

    var body: some View {
        Form {
            Section {
                Picker(selection: preferredDevice) {
                    Text("Follow System").tag(String?.none)
                    ForEach(controller.outputDevices) { device in
                        Label(device.name, systemImage: device.symbolName).tag(Optional(device.uid))
                    }
                    if let uid = preferences.preferredOutputDeviceUID, !controller.outputDevices.contains(where: { $0.uid == uid }) {
                        Text("\(preferences.preferredOutputDeviceName ?? "Unknown device") (not connected)").tag(Optional(uid))
                    }
                } label: {
                    Text("Default output device")
                    Text("Selected at launch and whenever the device connects.")
                }
            }

            Section {
                Toggle(isOn: $preferences.rememberAppVolumes) {
                    Text("Remember application volumes")
                    Text("Restores each app's volume by bundle identifier, including after it relaunches.")
                }
                Toggle(isOn: $preferences.showInactiveApps) {
                    Text("Show inactive applications")
                    Text("Also list apps that are connected to Core Audio but silent.")
                }
                Button("Reset All Application Volumes…", role: .destructive, action: confirmReset)
            }

            Section("Permission") {
                LabeledContent("System Audio Recording") {
                    HStack(spacing: 6) {
                        if controller.isCheckingCaptureAccess {
                            ProgressView().controlSize(.mini)
                        }
                        Text(permissionStatus).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Open Privacy Settings…", action: SystemSettingsLink.openAudioCapturePrivacy)
                    Button("Check Again", action: controller.recheckCaptureAuthorization)
                        .disabled(controller.isCheckingCaptureAccess)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all application volumes?"
        alert.informativeText = "Every app returns to 100% and unmuted. This can't be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            controller.resetAllVolumes()
        }
    }

    private var preferredDevice: Binding<String?> {
        Binding(
            get: { preferences.preferredOutputDeviceUID },
            set: { uid in
                preferences.preferredOutputDeviceUID = uid
                if let uid, let device = controller.outputDevices.first(where: { $0.uid == uid }) {
                    preferences.preferredOutputDeviceName = device.name
                }
            }
        )
    }

    private var permissionStatus: String {
        if controller.isTapProcessingDisabled { return "Disabled (--disable-taps)" }
        switch controller.captureAuthorization {
        case .unknown: return "Not checked yet"
        case .authorized: return "Granted"
        case .notGranted: return "Not granted"
        case .unavailable: return "Unavailable"
        }
    }
}
