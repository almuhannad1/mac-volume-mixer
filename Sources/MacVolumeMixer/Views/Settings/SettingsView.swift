import SwiftUI

struct SettingsView: View {
    let preferences: AppPreferences
    let loginItems: LoginItemService
    let controller: MixerController

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences, loginItems: loginItems)
                .tabItem { Label("General", systemImage: "gearshape") }
            AudioSettingsView(preferences: preferences, controller: controller)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 440)
    }
}
