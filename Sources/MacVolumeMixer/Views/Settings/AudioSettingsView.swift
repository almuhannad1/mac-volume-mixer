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
                Toggle(isOn: $preferences.perDeviceVolumes) {
                    Text("Remember a level per output device")
                    Text("Keeps separate volumes for speakers and headphones, so switching output doesn't carry the wrong level over.")
                }
                Toggle(isOn: $preferences.showInactiveApps) {
                    Text("Show inactive applications")
                    Text("Also list apps that are connected to Core Audio but silent.")
                }
                Button("Reset All Application Volumes…", role: .destructive, action: confirmReset)
            }

            Section("Calls") {
                Toggle(isOn: $preferences.duckDuringCalls) {
                    Text("Dim other apps during calls")
                    Text("While an app has the microphone open, everything else drops to the level below and returns when the call ends.")
                }
                Picker("Dim other apps to", selection: $preferences.duckLevel) {
                    Text("10%").tag(0.1)
                    Text("20%").tag(0.2)
                    Text("30%").tag(0.3)
                    Text("50%").tag(0.5)
                    Text("70%").tag(0.7)
                }
                .disabled(!preferences.duckDuringCalls)
            }

            Section("Processing") {
                Toggle(isOn: $preferences.lowLatencyProcessing) {
                    Text("Low-latency processing")
                    Text("Asks the output device for a smaller buffer while an app is being processed. Saves about 5 ms, but doubles how often the audio thread wakes, so it uses more battery.")
                }
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
