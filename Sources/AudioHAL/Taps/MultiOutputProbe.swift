import CoreAudio
import Darwin
import MixerCore

/// Feasibility probe: can one private aggregate device carry a process tap **and two real output
/// devices at once**, so a single app's audio can be rendered to both?
///
/// This is the question behind "listen together on two sets of AirPods". It reports the stream
/// layout the HAL actually gives us, because that decides whether each destination can have its
/// own volume (separate streams/channels) or must share one (mirrored).
public enum MultiOutputProbe {
    public struct Layout: Sendable {
        public let aggregateName: String
        public let outputStreamChannelCounts: [Int]
        public let inputStreamChannelCounts: [Int]
        public let sampleRate: Double
        public let startedIO: Bool
        public let note: String

        public var totalOutputChannels: Int { outputStreamChannelCounts.reduce(0, +) }
    }

    /// Can a tap render into a **Multi-Output Device** the user built in Audio MIDI Setup?
    ///
    /// That would mean today's per-app routing already solves "two sets of AirPods" with no new
    /// code. It requires nesting one aggregate device inside another, which Core Audio has
    /// historically refused, so it has to be tested rather than assumed.
    public static func probeNested(deviceUIDs: [String]) throws -> Layout {
        let outerUID = "MacVolumeMixerProbeMultiOut-" + UUID().uuidString
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Probe Multi-Output",
            kAudioAggregateDeviceUIDKey: outerUID,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUIDs[0],
            kAudioAggregateDeviceIsStackedKey: true, // what Audio MIDI Setup calls a Multi-Output Device
            kAudioAggregateDeviceSubDeviceListKey: deviceUIDs.enumerated().map { index, uid in
                index == 0
                    ? [kAudioSubDeviceUIDKey: uid]
                    : [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: UInt32(1)]
            },
        ]
        var outerID = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioError.check(
            AudioHardwareCreateAggregateDevice(composition as CFDictionary, &outerID),
            "Creating the stand-in Multi-Output Device"
        )
        defer { AudioHardwareDestroyAggregateDevice(outerID) }

        // Now the real question: a tap aggregate whose sub-device is that multi-output device.
        return try probe(deviceUIDs: [outerUID], stacked: false)
    }

    /// - Parameter deviceUIDs: the first is the clock main; the rest are drift-compensated.
    public static func probe(deviceUIDs: [String], stacked: Bool) throws -> Layout {
        guard deviceUIDs.count >= 1 else { throw CoreAudioError.missingObject("no device UIDs given") }
        guard let ownProcess = AudioProcessMonitor.processObjectID(forPID: getpid()) else {
            throw CoreAudioError.missingObject("this process is not registered with Core Audio")
        }

        let tapUUID = UUID()
        let description = CATapDescription(stereoMixdownOfProcesses: [ownProcess])
        description.name = "Mac Volume Mixer – Multi Probe"
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioError.check(AudioHardwareCreateProcessTap(description, &tapID), "Creating probe tap")
        defer { AudioHardwareDestroyProcessTap(tapID) }

        let subDevices: [[String: Any]] = deviceUIDs.enumerated().map { index, uid in
            index == 0
                ? [kAudioSubDeviceUIDKey: uid]
                : [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: UInt32(1)]
        }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mac Volume Mixer – Multi Probe",
            kAudioAggregateDeviceUIDKey: HALConstants.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUIDs[0],
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: stacked,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioError.check(
            AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID),
            "Creating multi-output aggregate"
        )
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }

        let outputs = HAL.streamFormats(aggregateID, scope: kAudioObjectPropertyScopeOutput)
        let inputs = HAL.streamFormats(aggregateID, scope: kAudioObjectPropertyScopeInput)
        let name = (try? HAL.readString(aggregateID, HAL.address(kAudioObjectPropertyName))) ?? "?"
        let rate = (try? HAL.read(aggregateID, HAL.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))) ?? 0

        // Prove IO can actually run: write silence for a moment, then stop.
        var startedIO = false
        var note = ""
        var ioProcID: AudioDeviceIOProcID?
        let block: AudioDeviceIOBlock = { _, _, _, outputData, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in buffers {
                if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
            }
        }
        if AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil, block) == noErr, let ioProcID {
            let status = AudioDeviceStart(aggregateID, ioProcID)
            startedIO = status == noErr
            if !startedIO { note = "AudioDeviceStart failed: \(FourCharCode.describe(status: status))" }
            Thread.sleep(forTimeInterval: 0.6)
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        } else {
            note = "could not create an IOProc"
        }

        return Layout(
            aggregateName: name,
            outputStreamChannelCounts: outputs.map { Int($0.mChannelsPerFrame) },
            inputStreamChannelCounts: inputs.map { Int($0.mChannelsPerFrame) },
            sampleRate: rate,
            startedIO: startedIO,
            note: note
        )
    }
}
