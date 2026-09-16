import AudioToolbox
import CoreAudio

/// Reads, writes and observes the hardware volume and mute of one output device
/// (the system "master" volume when bound to the default output device).
@MainActor
public final class DeviceVolumeController {
    /// `nil` when the device has no software volume control (e.g. many HDMI/USB devices).
    public private(set) var volume: Float?
    public private(set) var isMuted = false
    public private(set) var canMute = false
    public private(set) var deviceID = AudioObjectID(kAudioObjectUnknown)

    public var onChange: (() -> Void)?

    private var volumeAddresses: [AudioObjectPropertyAddress] = []
    private var muteAddresses: [AudioObjectPropertyAddress] = []
    private var listeners: [PropertyListener] = []

    public init() {}

    public func bind(to deviceID: AudioObjectID) {
        guard deviceID != self.deviceID else { return }
        self.deviceID = deviceID
        volumeAddresses = Self.settableAddresses(deviceID, candidates: Self.volumeCandidates)
        muteAddresses = Self.settableAddresses(deviceID, candidates: Self.muteCandidates)

        let handler: @MainActor () -> Void = { [weak self] in self?.refresh() }
        listeners = (volumeAddresses + muteAddresses).map {
            PropertyListener(objectID: deviceID, address: $0, handler: handler)
        }
        refresh()
    }

    public func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        for address in volumeAddresses {
            do { try HAL.write(deviceID, address, value: Float32(clamped)) } catch { break }
        }
        refresh()
    }

    public func setMuted(_ muted: Bool) {
        for address in muteAddresses {
            do { try HAL.write(deviceID, address, value: UInt32(muted ? 1 : 0)) } catch { break }
        }
        refresh()
    }

    private func refresh() {
        let volumes = volumeAddresses.compactMap { try? HAL.read(deviceID, $0, initial: Float32(0)) }
        let newVolume = volumes.isEmpty ? nil : volumes.reduce(0, +) / Float(volumes.count)
        let newMuted = muteAddresses.contains { (try? HAL.readBool(deviceID, $0)) ?? false }
        let newCanMute = !muteAddresses.isEmpty
        guard newVolume != volume || newMuted != isMuted || newCanMute != canMute else { return }
        volume = newVolume
        isMuted = newMuted
        canMute = newCanMute
        onChange?()
    }

    // The virtual main volume (AudioToolbox) is what the menu bar and keyboard keys drive; it
    // balances multichannel devices. Fall back to the main element, then to the first two channels.
    private static let volumeCandidates: [[AudioObjectPropertyAddress]] = [
        [HAL.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)],
        [HAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput)],
        [HAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 1),
         HAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 2)],
    ]

    private static let muteCandidates: [[AudioObjectPropertyAddress]] = [
        [HAL.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)],
        [HAL.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: 1),
         HAL.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: 2)],
    ]

    private static func settableAddresses(_ deviceID: AudioObjectID, candidates: [[AudioObjectPropertyAddress]]) -> [AudioObjectPropertyAddress] {
        for group in candidates {
            let usable = group.filter { HAL.hasProperty(deviceID, $0) && HAL.isSettable(deviceID, $0) }
            if !usable.isEmpty { return usable }
        }
        return []
    }
}
