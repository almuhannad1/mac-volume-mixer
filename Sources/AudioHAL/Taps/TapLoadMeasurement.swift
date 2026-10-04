import CoreAudio
import Darwin
import MixerCore

/// Measures what a given number of running taps actually costs in CPU and thread wake-ups.
///
/// Taps are placed on **this** process, `.unmuted`, so no other application is affected and no
/// audio changes. The IOProc still fires at the device's full buffer rate, which is the cost being
/// measured: a tap's expense comes from the realtime callback rate, not from the tapped app's audio.
///
/// Used to answer bug reports about power and CPU with numbers rather than guesses.
public enum TapLoadMeasurement {
    public struct Result: Sendable {
        public let tapCount: Int
        public let bufferFrames: UInt32
        public let sampleRate: Double
        public let seconds: Double
        /// Share of one core, as Activity Monitor would show it.
        public let cpuPercent: Double
        /// Thread wake-ups per second: the figure that drives battery drain.
        public let wakeupsPerSecond: Double
        public let footprintBytes: UInt64

        /// Expected realtime callbacks per second across every running tap.
        public var expectedCallbacksPerSecond: Double {
            bufferFrames == 0 ? 0 : sampleRate / Double(bufferFrames) * Double(tapCount)
        }
    }

    /// - Parameter bufferFrames: `nil` leaves each aggregate device at its own default size.
    public static func run(tapCount: Int, bufferFrames: UInt32?, seconds: Double) throws -> Result {
        let deviceID = try HAL.read(HAL.systemObject, HAL.address(kAudioHardwarePropertyDefaultOutputDevice),
                                    initial: AudioObjectID(kAudioObjectUnknown))
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw CoreAudioError.missingObject("default output device")
        }
        let uid = try HAL.readString(deviceID, HAL.address(kAudioDevicePropertyDeviceUID))
        guard let ownProcess = AudioProcessMonitor.processObjectID(forPID: getpid()) else {
            throw CoreAudioError.missingObject("this process is not registered with Core Audio")
        }

        var resources: [TapResources] = []
        defer { resources.forEach { $0.destroy() } }
        for index in 0..<max(tapCount, 0) {
            let tap = try TapResources.make(
                name: "Load \(index + 1)", processObjectIDs: [ownProcess], outputDeviceUID: uid,
                muteBehavior: .unmuted, gainLeft: AtomicFloat(0), gainRight: AtomicFloat(0),
                monoFlag: AtomicFloat(0), peak: AtomicFloat(0), preferredBufferFrames: bufferFrames
            )
            resources.append(tap)
            try tap.start()
        }

        // Let the realtime threads reach steady state before the clock starts.
        Thread.sleep(forTimeInterval: 1)
        let start = Snapshot.take()
        Thread.sleep(forTimeInterval: seconds)
        let end = Snapshot.take()

        let effectiveBuffer = resources.first.map { effectiveBufferFrames(of: $0) }
            ?? bufferFrames ?? 0
        return Result(
            tapCount: resources.count,
            bufferFrames: effectiveBuffer,
            sampleRate: sampleRate(of: deviceID),
            seconds: end.wall - start.wall,
            cpuPercent: (end.cpu - start.cpu) / (end.wall - start.wall) * 100,
            wakeupsPerSecond: Double(end.wakeups - start.wakeups) / (end.wall - start.wall),
            footprintBytes: Snapshot.footprint()
        )
    }


    /// Times a full audio-process enumeration, which runs on every Core Audio notification.
    /// Returns the average milliseconds per scan and the number of processes seen.
    public static func measureProcessScan(iterations: Int = 20) -> (milliseconds: Double, processCount: Int) {
        var count = 0
        let start = Date()
        for _ in 0..<max(iterations, 1) {
            count = AudioProcessMonitor.readProcesses().count
        }
        let elapsed = Date().timeIntervalSince(start) / Double(max(iterations, 1))
        return (elapsed * 1000, count)
    }

    /// Times re-reading just the volatile state of one process object: what a notification now
    /// costs, as opposed to the full scan it used to trigger.
    public static func measureVolatileRefresh(iterations: Int = 20) -> Double {
        guard let objectID = AudioProcessMonitor.readProcessObjectIDs().first else { return 0 }
        let start = Date()
        for _ in 0..<max(iterations, 1) {
            _ = AudioProcessMonitor.readRunningOutput(objectID)
            _ = AudioProcessMonitor.readRunningInput(objectID)
            _ = AudioProcessMonitor.readOutputDevices(objectID)
        }
        return Date().timeIntervalSince(start) / Double(max(iterations, 1)) * 1000
    }

    private static func effectiveBufferFrames(of resources: TapResources) -> UInt32 {
        (try? HAL.read(resources.aggregateObjectID, HAL.address(kAudioDevicePropertyBufferFrameSize),
                       initial: UInt32(0))) ?? 0
    }

    private static func sampleRate(of deviceID: AudioObjectID) -> Double {
        (try? HAL.read(deviceID, HAL.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))) ?? 0
    }

    /// CPU time, context switches and wall clock for this whole process, realtime threads included.
    private struct Snapshot {
        let cpu: Double
        let wakeups: UInt64
        let wall: Double

        static func take() -> Snapshot {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
            return Snapshot(
                cpu: user + system,
                wakeups: UInt64(usage.ru_nvcsw) + UInt64(usage.ru_nivcsw),
                wall: Date().timeIntervalSinceReferenceDate
            )
        }

        /// Phys-footprint, which is the number Activity Monitor shows in its Memory column.
        static func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
        }
    }
}
