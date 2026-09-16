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
    /// `kAudioProcessPropertyDevices` in the output scope.
    public let outputDeviceIDs: [UInt32]

    public init(
        objectID: UInt32,
        pid: Int32,
        bundleID: String?,
        executablePath: String?,
        isRunningOutput: Bool,
        outputDeviceIDs: [UInt32] = []
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.isRunningOutput = isRunningOutput
        self.outputDeviceIDs = outputDeviceIDs
    }
}
