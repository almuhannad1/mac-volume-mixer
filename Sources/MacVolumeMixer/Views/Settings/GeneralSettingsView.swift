import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    let loginItems: LoginItemService

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }
                ))
                if loginItems.requiresApproval {
                    LabeledContent("Waiting for approval in System Settings") {
                        Button("Open Login Items…", action: loginItems.openSystemSettings)
                    }
                    .foregroundStyle(.secondary)
                }
                if let error = loginItems.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle(isOn: $preferences.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("When hidden, open Mac Volume Mixer again from Finder or Spotlight to return to Settings.")
                }
                Toggle(isOn: $preferences.openMixerAtLaunch) {
                    Text("Open mixer automatically")
                    Text("Shows the mixer panel when the app starts.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loginItems.refresh)
    }
}
