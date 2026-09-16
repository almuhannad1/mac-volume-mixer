import AudioHAL
import os

enum AppLog {
    static let mixer = Logger(subsystem: HALConstants.subsystem, category: "mixer")
    static let app = Logger(subsystem: HALConstants.subsystem, category: "app")
}
