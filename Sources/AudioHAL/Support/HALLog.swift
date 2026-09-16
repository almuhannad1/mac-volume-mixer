import os

public enum HALConstants {
    public static let subsystem = "dev.macvolumemixer.MacVolumeMixer"
    /// UID prefix of the private aggregate devices created by tap engines.
    public static let aggregateUIDPrefix = "dev.macvolumemixer.aggregate."
}

enum HALLog {
    static let hal = Logger(subsystem: HALConstants.subsystem, category: "hal")
    static let devices = Logger(subsystem: HALConstants.subsystem, category: "devices")
    static let processes = Logger(subsystem: HALConstants.subsystem, category: "processes")
    static let taps = Logger(subsystem: HALConstants.subsystem, category: "taps")
    static let permission = Logger(subsystem: HALConstants.subsystem, category: "permission")
}
