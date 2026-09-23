import Foundation
import Testing
@testable import MixerCore

struct PersistenceTests {
    private let speakers = "BuiltInSpeakerDevice"
    private let headphones = "AirPodsPro"

    @Test func settingsRoundTripByBundleIdentifier() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("com.spotify.client") { $0.setLevel(volume: 0.3, forDeviceUID: nil) }
        store.update("com.hnc.Discord") { $0.setLevel(isMuted: true, forDeviceUID: nil) }

        let reloaded = AppVolumeSettingsStore(persistence: persistence)
        #expect(reloaded.effectiveSetting(for: "com.spotify.client", deviceUID: nil).volume == 0.3)
        #expect(reloaded.effectiveSetting(for: "com.hnc.Discord", deviceUID: nil).isMuted)
        #expect(reloaded.effectiveSetting(for: "com.google.Chrome", deviceUID: nil) == .default)
    }

    @Test func defaultSettingsArePruned() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("a") { $0.setLevel(volume: 0.5, forDeviceUID: nil) }
        store.update("a") { $0.setLevel(volume: 1, forDeviceUID: nil) }
        #expect(store.allSettings.isEmpty)
        #expect(persistence.storage[AppVolumeSettingsStore.storageKey] == nil)
    }

    @Test func routingIsStoredEvenAtFullVolume() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("a") { $0.setRoute(deviceUID: headphones, deviceName: "AirPods Pro") }

        let reloaded = AppVolumeSettingsStore(persistence: persistence)
        let setting = reloaded.effectiveSetting(for: "a", deviceUID: nil)
        #expect(setting.routeDeviceUID == headphones)
        #expect(setting.volume == 1)
        #expect(!setting.isDefault) // needs a tap despite unity gain
        #expect(reloaded.setting(for: "a").outputDeviceName == "AirPods Pro")

        reloaded.update("a") { $0.setRoute(deviceUID: nil) }
        #expect(reloaded.allSettings.isEmpty)
    }

    @Test func perDeviceLevelsAreIndependent() {
        let store = AppVolumeSettingsStore(persistence: InMemoryPersistence())
        store.update("a") { $0.setLevel(volume: 0.4, forDeviceUID: speakers) }
        store.update("a") { $0.setLevel(volume: 0.15, forDeviceUID: headphones) }

        #expect(store.effectiveSetting(for: "a", deviceUID: speakers).volume == 0.4)
        #expect(store.effectiveSetting(for: "a", deviceUID: headphones).volume == 0.15)
        // An unseen device falls back to the most recent level rather than jumping to 100 %.
        #expect(store.effectiveSetting(for: "a", deviceUID: "usb").volume == 0.15)
        // Per-device memory off: the baseline applies.
        #expect(store.effectiveSetting(for: "a", deviceUID: nil).volume == 0.15)

        store.update("a") { $0.setLevel(isMuted: true, forDeviceUID: speakers) }
        #expect(store.effectiveSetting(for: "a", deviceUID: speakers).isMuted)
        #expect(!store.effectiveSetting(for: "a", deviceUID: headphones).isMuted)
        #expect(store.effectiveSetting(for: "a", deviceUID: headphones).volume == 0.15)
    }

    @Test func settingsWrittenByVersion1StillLoad() throws {
        // Guards the promise that 1.1 needs no migration.
        let legacy = Data(#"{"com.spotify.client":{"volume":0.3,"isMuted":false},"com.hnc.Discord":{"volume":1,"isMuted":true}}"#.utf8)
        let persistence = InMemoryPersistence()
        persistence.setData(legacy, forKey: AppVolumeSettingsStore.storageKey)

        let store = AppVolumeSettingsStore(persistence: persistence)
        #expect(store.effectiveSetting(for: "com.spotify.client", deviceUID: "anything").volume == 0.3)
        #expect(store.effectiveSetting(for: "com.hnc.Discord", deviceUID: nil).isMuted)
        #expect(store.setting(for: "com.spotify.client").outputDeviceUID == nil)
        #expect(store.setting(for: "com.spotify.client").perDevice.isEmpty)
    }

    @Test func disablingPersistenceErasesStoredDataButKeepsSession() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("a") { $0.setLevel(volume: 0.2, forDeviceUID: nil) }
        store.isPersistenceEnabled = false
        #expect(persistence.storage.isEmpty)
        store.update("b") { $0.setLevel(isMuted: true, forDeviceUID: nil) }
        #expect(persistence.storage.isEmpty)
        #expect(store.effectiveSetting(for: "a", deviceUID: nil).volume == 0.2)

        store.isPersistenceEnabled = true
        #expect(AppVolumeSettingsStore(persistence: persistence).allSettings.count == 2)
    }

    @Test func storeStartsEmptyWhenPersistenceDisabled() {
        let persistence = InMemoryPersistence()
        AppVolumeSettingsStore(persistence: persistence).update("a") { $0.setLevel(volume: 0.2, forDeviceUID: nil) }
        #expect(AppVolumeSettingsStore(persistence: persistence, isPersistenceEnabled: false).allSettings.isEmpty)
    }

    @Test func corruptDataIsDiscarded() {
        let persistence = InMemoryPersistence()
        persistence.setData(Data("not json".utf8), forKey: AppVolumeSettingsStore.storageKey)
        #expect(AppVolumeSettingsStore(persistence: persistence).allSettings.isEmpty)
    }

    @Test func decodingClampsOutOfRangeValues() throws {
        let setting = try JSONDecoder().decode(AppVolumeSetting.self, from: Data(#"{"volume": 4}"#.utf8))
        #expect(setting.volume == 1)
        #expect(AppVolumeSetting(volume: -3).volume == 0)
        #expect(AppVolumeSetting(volume: .nan).volume == 1)
        #expect(EffectiveAppSetting(volume: 0.354, isMuted: false).percent == 35)
    }
}

struct DeviceTests {
    @Test func transportCodesDecode() {
        #expect(AudioTransportType(code: 1_651_274_862) == .builtIn) // 'bltn' observed on this Mac
        #expect(AudioTransportType(code: 1_970_496_032) == .usb)     // 'usb '
        #expect(AudioTransportType(code: 1_751_412_073) == .hdmi)    // 'hdmi'
        #expect(AudioTransportType(code: 1_986_622_068) == .virtual) // 'virt'
        #expect(AudioTransportType(code: 42) == .unknown(42))
    }

    @Test func fourCharCodeFormatting() {
        #expect(FourCharCode.string(from: FourCharCode.make("who?")) == "who?")
        #expect(FourCharCode.describe(status: Int32(bitPattern: FourCharCode.make("!obj"))) == "'!obj' (560947818)")
        #expect(FourCharCode.describe(status: -50) == "-50")
    }

    @Test func selectableDevicesExcludeInputsHiddenAndOwnAggregates() {
        func device(_ id: UInt32, _ name: String, uid: String, channels: Int = 2, hidden: Bool = false) -> AudioOutputDevice {
            AudioOutputDevice(id: id, uid: uid, name: name, transportType: .builtIn, outputChannelCount: channels, isHidden: hidden)
        }
        let devices = [
            device(1, "MacBook Pro Speakers", uid: "BuiltInSpeakerDevice"),
            device(2, "MacBook Pro Microphone", uid: "BuiltInMicrophoneDevice", channels: 0),
            device(3, "Hidden", uid: "hidden", hidden: true),
            device(4, "Mixer Tap", uid: "dev.macvolumemixer.aggregate.1"),
            device(5, "AirPods Pro", uid: "airpods"),
        ]
        let selectable = OutputDeviceFilter.selectable(devices, excludingUIDPrefix: "dev.macvolumemixer.aggregate.")
        #expect(selectable.map(\.id) == [5, 1])
        #expect(selectable[0].symbolName == "airpodspro")
        #expect(selectable[1].symbolName == "laptopcomputer")
    }
}
