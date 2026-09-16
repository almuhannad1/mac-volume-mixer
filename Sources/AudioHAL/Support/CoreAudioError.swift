import CoreAudio
import MixerCore

public enum CoreAudioError: Error, CustomStringConvertible, Sendable {
    case status(OSStatus, operation: String)
    case unsupportedFormat(String)
    case missingObject(String)

    public var description: String {
        switch self {
        case let .status(status, operation): "\(operation) failed with \(FourCharCode.describe(status: status))"
        case let .unsupportedFormat(detail): "Unsupported audio format: \(detail)"
        case let .missingObject(detail): "Audio object unavailable: \(detail)"
        }
    }

    /// Throws (and logs) when `status` is not `noErr`.
    static func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
        guard status != noErr else { return }
        let error = CoreAudioError.status(status, operation: operation())
        HALLog.hal.error("\(error.description, privacy: .public)")
        throw error
    }
}
