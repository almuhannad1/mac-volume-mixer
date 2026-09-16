import CoreAudio
import Darwin
import Foundation
import MixerCore

public enum AudioCaptureAuthorization: Equatable, Sendable {
    case unknown
    /// Taps deliver real audio.
    case authorized
    /// Taps deliver silence: the System Audio Recording permission is missing, denied, or its
    /// prompt has not been answered yet. macOS offers no public API to tell these apart.
    case notGranted
    /// The self-test could not run (e.g. no output device).
    case unavailable(String)
}

/// Detects whether this app may read process taps.
///
/// There is no public API for the "System Audio Recording" TCC status, and an unauthorized tap
/// simply delivers silence. Engaging a *muting* tap in that state would silence the user's apps,
/// so before any engine runs, this loopback self-test:
///
/// 1. taps **this** process with `.unmuted` behavior (nothing the user hears changes),
/// 2. plays an inaudible −90 dBFS, 30 Hz signal from this process,
/// 3. reports `.authorized` only if that signal comes back through the tap.
///
/// Reading the tap is also what makes macOS show the permission prompt the first time.
public enum AudioCapturePermissionProbe {
    private static let probeQueue = DispatchQueue(label: "dev.macvolumemixer.permission-probe", qos: .userInitiated)
    private static let toneAmplitude: Float = 3e-5
    private static let detectionThreshold: Float = 3e-6

    public static func check(outputDeviceID: AudioObjectID, timeout: TimeInterval = 2) async -> AudioCaptureAuthorization {
        await withCheckedContinuation { continuation in
            probeQueue.async {
                continuation.resume(returning: run(outputDeviceID: outputDeviceID, timeout: timeout))
            }
        }
    }

    private static func run(outputDeviceID: AudioObjectID, timeout: TimeInterval) -> AudioCaptureAuthorization {
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown),
              let outputUID = try? HAL.readString(outputDeviceID, HAL.address(kAudioDevicePropertyDeviceUID)) else {
            return .unavailable("No output device is available.")
        }
        guard let ownProcess = AudioProcessMonitor.processObjectID(forPID: getpid()) else {
            return .unavailable("Core Audio does not list this app as an audio process.")
        }

        let gain = AtomicFloat(0) // monitor only: write silence to the device
        let peak = AtomicFloat(0)
        let resources: TapResources
        let tone: ProbeTone
        do {
            resources = try TapResources.make(
                name: "Permission Check", processObjectIDs: [ownProcess], outputDeviceUID: outputUID,
                muteBehavior: .unmuted, gain: gain, peak: peak
            )
        } catch {
            return .unavailable(String(describing: error))
        }
        defer { resources.destroy() }

        do {
            tone = try ProbeTone(deviceID: outputDeviceID, amplitude: toneAmplitude)
            try resources.start()
        } catch {
            return .unavailable(String(describing: error))
        }
        defer { tone.stop() }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if peak.load() > detectionThreshold {
                HALLog.permission.info("Audio capture self-test passed")
                return .authorized
            }
            usleep(50_000)
        }
        HALLog.permission.notice("Audio capture self-test received silence; System Audio Recording is not granted")
        return .notGranted
    }
}

/// A near-silent sine written straight to an output device from this process.
private final class ProbeTone {
    private let deviceID: AudioObjectID
    private var ioProcID: AudioDeviceIOProcID?
    private let phase = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    init(deviceID: AudioObjectID, amplitude: Float) throws {
        self.deviceID = deviceID
        phase.initialize(to: 0)
        let sampleRate = (try? HAL.read(deviceID, HAL.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(48_000))) ?? 48_000
        let increment = Float(2 * Double.pi * 30 / sampleRate)
        let phase = self.phase

        let block: AudioDeviceIOBlock = { _, _, _, outputData, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            var endPhase = phase.pointee
            for buffer in buffers {
                guard let bytes = buffer.mData, buffer.mNumberChannels > 0 else { continue }
                let channels = Int(buffer.mNumberChannels)
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                let samples = bytes.assumingMemoryBound(to: Float.self)
                var current = phase.pointee
                for frame in 0..<frames {
                    let value = amplitude * sin(current)
                    for channel in 0..<channels { samples[frame * channels + channel] = value }
                    current += increment
                    if current > 2 * .pi { current -= 2 * .pi }
                }
                endPhase = current
            }
            phase.pointee = endPhase
        }

        try CoreAudioError.check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, deviceID, nil, block), "Creating probe tone IOProc")
        guard let ioProcID else { throw CoreAudioError.missingObject("probe tone IOProc") }
        do {
            try CoreAudioError.check(AudioDeviceStart(deviceID, ioProcID), "Starting probe tone")
        } catch {
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            self.ioProcID = nil
            throw error
        }
    }

    func stop() {
        guard let ioProcID else { return }
        AudioDeviceStop(deviceID, ioProcID)
        AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        self.ioProcID = nil
    }

    deinit {
        stop()
        phase.deallocate()
    }
}
