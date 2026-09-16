/// Formatting helpers for Core Audio four-character codes and `OSStatus` values.
public enum FourCharCode {
    /// Builds a code from a four-character ASCII string, e.g. `FourCharCode.make("bltn")`.
    public static func make(_ string: StaticString) -> UInt32 {
        precondition(string.utf8CodeUnitCount == 4, "Four-character codes need exactly four ASCII characters")
        let bytes = string.utf8Start
        return (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[$1]) }
    }

    /// Returns `'abcd'` when every byte is printable ASCII, otherwise `nil`.
    public static func string(from code: UInt32) -> String? {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Human-readable description of an `OSStatus`, e.g. `'!obj' (560947818)`.
    public static func describe(status: Int32) -> String {
        if let text = string(from: UInt32(bitPattern: status)) {
            return "'\(text)' (\(status))"
        }
        return "\(status)"
    }
}
