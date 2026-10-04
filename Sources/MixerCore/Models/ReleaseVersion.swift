/// A release version, parsed from a tag such as `v1.2.0` or a bundle's `CFBundleShortVersionString`.
///
/// Compared numerically, so 1.10.0 is correctly newer than 1.9.0 — a plain string comparison gets
/// that backwards.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1`, `1.2`, `1.2.3` and a leading `v`. Pre-release and build metadata are ignored,
    /// so `1.3.0-beta.1` compares as `1.3.0`. Returns `nil` for anything else.
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        if let separator = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            trimmed = String(trimmed[trimmed.startIndex..<separator])
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        func component(_ index: Int) -> Int? {
            guard index < parts.count else { return 0 } // "1.2" means 1.2.0
            return Int(parts[index])
        }
        guard !parts.isEmpty, let major = component(0), let minor = component(1), let patch = component(2),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
