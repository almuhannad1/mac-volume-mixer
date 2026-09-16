import Foundation
import Testing
@testable import MixerCore

struct PersistenceTests {
    @Test func settingsRoundTripByBundleIdentifier() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("com.spotify.client") { $0.setVolume(0.3) }
        store.update("com.hnc.Discord") { $0.isMuted = true }

        let reloaded = AppVolumeSettingsStore(persistence: persistence)
        #expect(reloaded.setting(for: "com.spotify.client") == AppVolumeSetting(volume: 0.3))
        #expect(reloaded.setting(for: "com.hnc.Discord").isMuted)
        #expect(reloaded.setting(for: "com.google.Chrome") == .default)
    }

    @Test func defaultSettingsArePruned() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("a") { $0.setVolume(0.5) }
        store.update("a") { $0.setVolume(1) }
        #expect(store.allSettings.isEmpty)
        #expect(persistence.storage[AppVolumeSettingsStore.storageKey] == nil)
    }

    @Test func disablingPersistenceErasesStoredDataButKeepsSession() {
        let persistence = InMemoryPersistence()
        let store = AppVolumeSettingsStore(persistence: persistence)
        store.update("a") { $0.setVolume(0.2) }
        store.isPersistenceEnabled = false
        #expect(persistence.storage.isEmpty)
        store.update("b") { $0.isMuted = true }
        #expect(persistence.storage.isEmpty)
        #expect(store.setting(for: "a").volume == 0.2)

        store.isPersistenceEnabled = true
        #expect(AppVolumeSettingsStore(persistence: persistence).allSettings.count == 2)
    }

    @Test func storeStartsEmptyWhenPersistenceDisabled() {
        let persistence = InMemoryPersistence()
        AppVolumeSettingsStore(persistence: persistence).update("a") { $0.setVolume(0.2) }
        #expect(AppVolumeSettingsStore(persistence: persistence, isPersistenceEnabled: false).allSettings.isEmpty)
    }

    @Test func corruptDataIsDiscarded() {
        let persistence = InMemoryPersistence()
        persistence.setData(Data("not json".utf8), forKey: AppVolumeSettingsStore.storageKey)
        #expect(AppVolumeSettingsStore(persistence: persistence).allSettings.isEmpty)
    }

    @Test func decodingClampsOutOfRangeValues() throws {
        let data = Data(#"{"volume": 4, "isMuted": false}"#.utf8)
        let setting = try JSONDecoder().decode(AppVolumeSetting.self, from: data)
        #expect(setting.volume == 1)
        #expect(AppVolumeSetting(volume: -3).volume == 0)
        #expect(AppVolumeSetting(volume: .nan).volume == 1)
        #expect(AppVolumeSetting(volume: 0.354).percent == 35)
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
