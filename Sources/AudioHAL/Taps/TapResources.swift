import CoreAudio
import Foundation
import MixerCore
import RealtimeAtomics

/// The Core Audio objects that route one app's audio through a gain stage:
///
///     process tap (mutes the app at the HAL, exposes its audio as a stream)
///       └▶ private aggregate device (main sub-device = real output device, tap as input)
///            └▶ IOProc: tap input × gain → device output
///
/// Not thread-safe: every method must be called on the owning engine's serial queue.
final class TapResources {
    let outputDeviceUID: String
    private(set) var processObjectIDs: [AudioObjectID]
    private(set) var isRunning = false

    private let name: String
    private let tapUUID: UUID
    private let muteBehavior: CATapMuteBehavior
    private let tapID: AudioObjectID
    private let aggregateID: AudioObjectID
    private let ioProcID: AudioDeviceIOProcID
    /// Gain applied at the end of the previous render cycle. Written only by the IO thread
    /// while running, and only by the queue while stopped.
    private let rampGain: UnsafeMutablePointer<Float>
    private var isDestroyed = false

    private init(
        name: String, tapUUID: UUID, muteBehavior: CATapMuteBehavior, processObjectIDs: [AudioObjectID],
        outputDeviceUID: String, tapID: AudioObjectID, aggregateID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID, rampGain: UnsafeMutablePointer<Float>
    ) {
        self.name = name
        self.tapUUID = tapUUID
        self.muteBehavior = muteBehavior
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.tapID = tapID
        self.aggregateID = aggregateID
        self.ioProcID = ioProcID
        self.rampGain = rampGain
    }

    deinit {
        assert(isDestroyed, "TapResources must be destroyed explicitly on the engine queue")
    }

    /// Creates the tap, aggregate device and IOProc (not started).
    ///
    /// - Parameters:
    ///   - gain: atomic cell holding the linear gain to apply.
    ///   - peak: atomic cell that accumulates the pre-gain input peak.
    static func make(
        name: String,
        processObjectIDs: [AudioObjectID],
        outputDeviceUID: String,
        muteBehavior: CATapMuteBehavior,
        gain: AtomicFloat,
        peak: AtomicFloat
    ) throws -> TapResources {
        var rollback: [() -> Void] = []
        do {
            let tapUUID = UUID()
            let description = makeDescription(name: name, uuid: tapUUID, processObjectIDs: processObjectIDs, muteBehavior: muteBehavior)
            var tapID = AudioObjectID(kAudioObjectUnknown)
            try CoreAudioError.check(AudioHardwareCreateProcessTap(description, &tapID), "Creating process tap for \(name)")
            rollback.append { AudioHardwareDestroyProcessTap(tapID) }

            let tapFormat = try HAL.read(tapID, HAL.address(kAudioTapPropertyFormat), initial: AudioStreamBasicDescription())
            guard HAL.isFloat32LinearPCM(tapFormat) else {
                throw CoreAudioError.unsupportedFormat("tap for \(name) delivers \(tapFormat)")
            }

            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            let composition = aggregateComposition(name: name, outputDeviceUID: outputDeviceUID, tapUUID: tapUUID)
            try CoreAudioError.check(
                AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID),
                "Creating aggregate device for \(name)"
            )
            rollback.append { AudioHardwareDestroyAggregateDevice(aggregateID) }

            // Sub-device input streams (if the output device also has inputs) come first; the tap is last.
            let inputFormats = HAL.streamFormats(aggregateID, scope: kAudioObjectPropertyScopeInput)
            let outputFormats = HAL.streamFormats(aggregateID, scope: kAudioObjectPropertyScopeOutput)
            guard let tapStreamFormat = inputFormats.last, HAL.isFloat32LinearPCM(tapStreamFormat) else {
                throw CoreAudioError.unsupportedFormat("aggregate input for \(name): \(inputFormats)")
            }
            guard let outputFormat = outputFormats.first, HAL.isFloat32LinearPCM(outputFormat) else {
                throw CoreAudioError.unsupportedFormat("aggregate output for \(name): \(outputFormats)")
            }
            if tapStreamFormat.mSampleRate != outputFormat.mSampleRate {
                HALLog.taps.notice("""
                    Tap for \(name, privacy: .public) runs at \(tapStreamFormat.mSampleRate) Hz but the output runs at \
                    \(outputFormat.mSampleRate) Hz; relying on aggregate drift compensation
                    """)
            }

            let rampGain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
            rampGain.initialize(to: 0)
            rollback.append { rampGain.deallocate() }

            var ioProcID: AudioDeviceIOProcID?
            let block = makeRenderBlock(gain: gain.rawPointer, peak: peak.rawPointer, rampGain: rampGain)
            // A nil queue runs the block directly on the HAL's realtime IO thread.
            try CoreAudioError.check(
                AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil, block),
                "Creating IOProc for \(name)"
            )
            guard let ioProcID else { throw CoreAudioError.missingObject("IOProc for \(name)") }

            HALLog.taps.info("""
                Engaged tap for \(name, privacy: .public): processes \(processObjectIDs), device \(outputDeviceUID, privacy: .public), \
                \(Int(outputFormat.mSampleRate)) Hz, \(outputFormat.mChannelsPerFrame) ch
                """)
            return TapResources(
                name: name, tapUUID: tapUUID, muteBehavior: muteBehavior, processObjectIDs: processObjectIDs,
                outputDeviceUID: outputDeviceUID, tapID: tapID, aggregateID: aggregateID, ioProcID: ioProcID, rampGain: rampGain
            )
        } catch {
            rollback.reversed().forEach { $0() }
            throw error
        }
    }

    func start() throws {
        guard !isRunning, !isDestroyed else { return }
        rampGain.pointee = 0 // fade in over the first buffer
        try CoreAudioError.check(AudioDeviceStart(aggregateID, ioProcID), "Starting IO for \(name)")
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        let status = AudioDeviceStop(aggregateID, ioProcID)
        if status != noErr {
            HALLog.taps.error("Stopping IO for \(self.name, privacy: .public) failed: \(FourCharCode.describe(status: status), privacy: .public)")
        }
        isRunning = false
    }

    /// Changes which processes feed the tap (e.g. Chrome spawned a new audio helper) without
    /// rebuilding the aggregate device.
    func updateProcesses(_ newProcessObjectIDs: [AudioObjectID]) throws {
        var description = Self.makeDescription(name: name, uuid: tapUUID, processObjectIDs: newProcessObjectIDs, muteBehavior: muteBehavior)
        var address = HAL.address(kAudioTapPropertyDescription)
        let status = withUnsafeMutablePointer(to: &description) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        try CoreAudioError.check(status, "Updating tap processes for \(name)")
        processObjectIDs = newProcessObjectIDs
    }

    func destroy() {
        guard !isDestroyed else { return }
        stop()
        // Order matters: the IOProc must be gone before the memory it reads is released.
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
        rampGain.deallocate()
        isDestroyed = true
        HALLog.taps.info("Released tap for \(self.name, privacy: .public)")
    }

    // MARK: - Construction helpers

    private static func makeDescription(
        name: String, uuid: UUID, processObjectIDs: [AudioObjectID], muteBehavior: CATapMuteBehavior
    ) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "Mac Volume Mixer – \(name)"
        description.uuid = uuid
        description.isPrivate = true
        description.muteBehavior = muteBehavior
        return description
    }

    private static func aggregateComposition(name: String, outputDeviceUID: String, tapUUID: UUID) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "Mac Volume Mixer – \(name)",
            kAudioAggregateDeviceUIDKey: HALConstants.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
    }

    /// Builds the realtime render block. It captures only raw pointers and plain values, so
    /// rendering performs no allocation, locking, reference counting or Objective-C messaging.
    private static func makeRenderBlock(
        gain: OpaquePointer,
        peak: OpaquePointer,
        rampGain: UnsafeMutablePointer<Float>
    ) -> AudioDeviceIOBlock {
        { _, inputData, _, outputData, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            let sampleSize = MemoryLayout<Float>.size
            let targetGain = rt_atomic_float_load(gain)
            var inputPeak: Float = 0
            var didRender = false
            // Taps are appended after the sub-device's own streams, so the tap is always the
            // last input buffer. Reading it positionally avoids assuming that stream index and
            // buffer index line up (they don't for non-interleaved sub-device streams).
            let tapBufferIndex = inputs.count - 1

            for outputIndex in 0..<outputs.count {
                let output = outputs[outputIndex]
                guard let outputBytes = output.mData else { continue }
                let outputChannels = Int(output.mNumberChannels)

                guard !didRender, outputChannels > 0, tapBufferIndex >= 0, tapBufferIndex < inputs.count,
                      let inputBytes = inputs[tapBufferIndex].mData, inputs[tapBufferIndex].mNumberChannels > 0
                else {
                    memset(outputBytes, 0, Int(output.mDataByteSize))
                    continue
                }

                let input = inputs[tapBufferIndex]
                let inputChannels = Int(input.mNumberChannels)
                let outputFrames = Int(output.mDataByteSize) / (sampleSize * outputChannels)
                let frames = min(outputFrames, Int(input.mDataByteSize) / (sampleSize * inputChannels))

                inputPeak = GainProcessor.render(
                    source: UnsafePointer(inputBytes.assumingMemoryBound(to: Float.self)),
                    sourceChannels: inputChannels,
                    destination: outputBytes.assumingMemoryBound(to: Float.self),
                    destinationChannels: outputChannels,
                    frameCount: frames,
                    startGain: rampGain.pointee,
                    endGain: targetGain
                )
                if frames < outputFrames {
                    let bytesPerFrame = sampleSize * outputChannels
                    memset(outputBytes + frames * bytesPerFrame, 0, (outputFrames - frames) * bytesPerFrame)
                }
                didRender = true
            }

            rampGain.pointee = targetGain
            rt_atomic_float_store_max(peak, inputPeak)
        }
    }
}
