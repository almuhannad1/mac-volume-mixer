/// Snapshot of one Core Audio `AudioProcess` object.
public struct AudioProcessInfo: Hashable, Sendable {
    /// The `AudioObjectID` of the process object.
    public let objectID: UInt32
    public let pid: Int32
    /// `kAudioProcessPropertyBundleID`; may be empty for daemons.
    public let bundleID: String?
    /// Executable path from `proc_pidpath`, if readable.
    public let executablePath: String?
    /// `kAudioProcessPropertyIsRunningOutput`.
    public let isRunningOutput: Bool
    /// `kAudioProcessPropertyIsRunningInput`: the process has the microphone open.
    public let isRunningInput: Bool
    /// `kAudioProcessPropertyDevices` in the output scope.
    public let outputDeviceIDs: [UInt32]

    public init(
        objectID: UInt32,
        pid: Int32,
        bundleID: String?,
        executablePath: String?,
        isRunningOutput: Bool,
        isRunningInput: Bool = false,
        outputDeviceIDs: [UInt32] = []
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.isRunningOutput = isRunningOutput
        self.isRunningInput = isRunningInput
        self.outputDeviceIDs = outputDeviceIDs
    }

    /// A copy with only the fields that can change while the process lives.
    ///
    /// `objectID`, `pid`, `bundleID` and `executablePath` are fixed for a given process object,
    /// so re-reading them from the HAL on every notification is wasted work.
    public func updating(isRunningOutput: Bool, isRunningInput: Bool, outputDeviceIDs: [UInt32]) -> AudioProcessInfo {
        AudioProcessInfo(
            objectID: objectID, pid: pid, bundleID: bundleID, executablePath: executablePath,
            isRunningOutput: isRunningOutput, isRunningInput: isRunningInput, outputDeviceIDs: outputDeviceIDs
        )
    }
}
