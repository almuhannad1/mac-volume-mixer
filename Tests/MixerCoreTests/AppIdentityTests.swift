import Testing
@testable import MixerCore

struct AppIdentityTests {
    private let resolver = AppIdentityResolver { path in
        switch path {
        case "/Applications/Discord.app": .init(identifier: "com.hnc.Discord", name: "Discord")
        case "/Applications/Google Chrome.app": .init(identifier: "com.google.Chrome", name: "Google Chrome")
        default: nil
        }
    }

    private func process(_ id: UInt32, pid: Int32, bundleID: String?, path: String?, playing: Bool = false, devices: [UInt32] = []) -> AudioProcessInfo {
        AudioProcessInfo(objectID: id, pid: pid, bundleID: bundleID, executablePath: path, isRunningOutput: playing, outputDeviceIDs: devices)
    }

    @Test func outermostBundleIsFound() {
        #expect(AppIdentityResolver.outermostAppBundlePath(
            inExecutablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)"
        ) == "/Applications/Discord.app")
        #expect(AppIdentityResolver.outermostAppBundlePath(inExecutablePath: "/usr/sbin/systemstats") == nil)
        #expect(AppIdentityResolver.outermostAppBundlePath(inExecutablePath: "/opt/.app/bin/tool") == nil)
    }

    @Test func helperResolvesToOwningApp() {
        let helper = process(1, pid: 10, bundleID: "com.hnc.Discord.helper.Renderer",
                             path: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)")
        let identity = resolver.identity(for: helper)
        #expect(identity.id == "com.hnc.Discord")
        #expect(identity.displayName == "Discord")
        #expect(identity.bundlePath == "/Applications/Discord.app")
        #expect(identity.kind == .application)
        #expect(identity.isUserFacing)
    }

    @Test func unreadableBundleFallsBackToReportedIDAndFolderName() {
        let identity = resolver.identity(for: process(1, pid: 1, bundleID: "com.spotify.client",
                                                      path: "/Applications/Spotify.app/Contents/MacOS/Spotify"))
        #expect(identity.id == "com.spotify.client")
        #expect(identity.displayName == "Spotify")
    }

    @Test func webKitProcessesAreGroupedAsKnownService() {
        let gpu = resolver.identity(for: process(1, pid: 1, bundleID: "com.apple.WebKit.GPU",
                                                 path: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"))
        #expect(gpu.id == "com.apple.WebKit")
        #expect(gpu.kind == .systemService)
        let sounds = resolver.identity(for: process(2, pid: 2, bundleID: nil, path: "/usr/sbin/systemsoundserverd"))
        #expect(sounds.displayName == "System Sounds")
    }

    @Test func systemAppsAndDaemonsAreNotUserFacing() {
        let controlCenter = resolver.identity(for: process(1, pid: 1, bundleID: "com.apple.controlcenter",
                                                           path: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"))
        #expect(!controlCenter.isUserFacing)
        let daemon = resolver.identity(for: process(2, pid: 2, bundleID: "com.apple.audiomxd", path: "/usr/libexec/audiomxd"))
        #expect(daemon.kind == .process)
        #expect(daemon.displayName == "audiomxd")
        let anonymous = resolver.identity(for: process(3, pid: 42, bundleID: "", path: nil))
        #expect(anonymous.id == "process:Process 42")
    }

    @Test func grouperMergesHelpersAndExcludesOwnProcess() {
        let processes = [
            process(5, pid: 100, bundleID: "com.hnc.Discord", path: "/Applications/Discord.app/Contents/MacOS/Discord"),
            process(3, pid: 101, bundleID: "com.hnc.Discord.helper.Renderer",
                    path: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)",
                    playing: true, devices: [77]),
            process(9, pid: 200, bundleID: "com.google.Chrome.helper",
                    path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
            process(1, pid: 999, bundleID: "dev.macvolumemixer.MacVolumeMixer", path: "/Applications/Mac Volume Mixer.app/Contents/MacOS/MacVolumeMixer"),
        ]
        let sessions = AudioSessionGrouper.group(processes, excludingPID: 999, resolver: resolver)
        #expect(sessions.map(\.id) == ["com.hnc.Discord", "com.google.Chrome"])
        let discord = sessions[0]
        #expect(discord.processObjectIDs == [3, 5])
        #expect(discord.isProducingOutput)
        #expect(discord.preferredOutputDeviceID == 77)
        #expect(!sessions[1].isProducingOutput)
    }

    @Test func mixerNeverListsItself() {
        // Tapping our own process would mute the audio we render for every other app.
        let processes = [
            process(1, pid: 100, bundleID: "dev.macvolumemixer.MacVolumeMixer",
                    path: "/Applications/Mac Volume Mixer.app/Contents/MacOS/MacVolumeMixer"),
            process(2, pid: 101, bundleID: "com.hnc.Discord", path: "/Applications/Discord.app/Contents/MacOS/Discord"),
        ]
        let sessions = AudioSessionGrouper.group(
            processes, excludingPID: 999, ownBundleID: "dev.macvolumemixer.MacVolumeMixer", resolver: resolver
        )
        #expect(sessions.map(\.id) == ["com.hnc.Discord"])
        // Without the bundle filter the second instance would still be listed.
        #expect(AudioSessionGrouper.group(processes, excludingPID: 999, resolver: resolver).count == 2)
    }

    @Test func preferredDeviceRequiresAgreement() {
        let identity = AppIdentity(id: "x", bundleIdentifier: nil, bundlePath: nil, displayName: "X", kind: .application)
        let disagree = AudioAppSession(identity: identity, processes: [
            process(1, pid: 1, bundleID: nil, path: nil, playing: true, devices: [1]),
            process(2, pid: 2, bundleID: nil, path: nil, playing: true, devices: [2]),
        ])
        #expect(disagree.preferredOutputDeviceID == nil)
        let silent = AudioAppSession(identity: identity, processes: [process(1, pid: 1, bundleID: nil, path: nil, devices: [1])])
        #expect(silent.preferredOutputDeviceID == nil)
    }
}
