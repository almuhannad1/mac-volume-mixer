import CoreAudio
import Darwin
import MixerCore

/// Builds a complete tap pipeline (process tap → private aggregate device → IOProc) against real
/// hardware and tears it down again **without starting IO**, so nothing is muted and macOS does
/// not show the audio-capture prompt.
///
/// Verifies everything that can be checked without the System Audio Recording permission:
/// object creation, format negotiation, aggregate composition and clean teardown.
public enum TapEngineSelfTest {
    public static func run() -> Result<String, Error> {
        let systemObject = HAL.systemObject
        do {
            let deviceID = try HAL.read(systemObject, HAL.address(kAudioHardwarePropertyDefaultOutputDevice),
                                        initial: AudioObjectID(kAudioObjectUnknown))
            guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
                throw CoreAudioError.missingObject("default output device")
            }
            let uid = try HAL.readString(deviceID, HAL.address(kAudioDevicePropertyDeviceUID))
            let name = (try? HAL.readString(deviceID, HAL.address(kAudioObjectPropertyName))) ?? uid
            guard let ownProcess = AudioProcessMonitor.processObjectID(forPID: getpid()) else {
                throw CoreAudioError.missingObject("this process is not registered with Core Audio")
            }

            // Tapping ourselves, unmuted: no other app is affected.
            let resources = try TapResources.make(
                name: "Self Test", processObjectIDs: [ownProcess], outputDeviceUID: uid,
                muteBehavior: .unmuted, gain: AtomicFloat(0), peak: AtomicFloat(0)
            )
            resources.destroy()
            return .success("Tap pipeline built and released successfully on “\(name)” (\(uid)).")
        } catch {
            return .failure(error)
        }
    }
}
