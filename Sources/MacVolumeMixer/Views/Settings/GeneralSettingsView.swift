import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    let loginItems: LoginItemService
    let updateChecker: UpdateChecker

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
                Toggle(isOn: $preferences.scrollOnMenuBarIcon) {
                    Text("Scroll over the menu bar icon to change volume")
                    Text("Middle-click the icon to mute.")
                }
            }

            Section("Updates") {
                Toggle(isOn: $preferences.checkForUpdatesAutomatically) {
                    Text("Check for updates automatically")
                    Text("Asks GitHub once a day whether a newer version exists — the only time this app uses the network. Nothing is downloaded or installed for you.")
                }
                LabeledContent("Version \(AppBundle.shortVersion ?? "development build")") {
                    HStack(spacing: 8) {
                        updateStatus
                        Button("Check Now", action: updateChecker.checkNow)
                            .disabled(updateChecker.state == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loginItems.refresh)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.mini)
        case let .upToDate(version):
            Text("Up to date (\(version.description))").foregroundStyle(.secondary)
        case let .available(release):
            Button("Version \(release.version.description) is available") {
                NSWorkspace.shared.open(release.url)
            }
            .buttonStyle(.link)
        case let .failed(message):
            Text(message).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
