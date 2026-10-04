import Foundation
import MixerCore
import Observation

/// Asks GitHub whether a newer release exists.
///
/// This is the only part of the app that uses the network, and it is **off by default**: nothing is
/// sent anywhere until the user turns automatic checking on, or presses Check Now themselves.
/// A manual check always works, so the feature stays usable without enabling background requests.
///
/// Nothing is ever installed. An update is reported with a link to the release page, because the
/// app is ad-hoc signed: replacing it changes its signature, which makes macOS ask for System Audio
/// Recording again. Doing that silently behind the user's back would leave the app looking broken.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable, Sendable {
        let version: ReleaseVersion
        let name: String
        let url: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(ReleaseVersion)
        case available(Release)
        /// The check could not complete (offline, rate-limited, unexpected response).
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var task: Task<Void, Never>?

    /// `/releases/latest` already excludes drafts and pre-releases.
    private static let endpoint = URL(string: "https://api.github.com/repos/almuhannad1/mac-volume-mixer/releases/latest")!

    init(preferences: AppPreferences) {
        self.preferences = preferences
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "MacVolumeMixer/\(AppBundle.shortVersion ?? "dev")",
        ]
        session = URLSession(configuration: configuration)
    }

    /// `nil` when the running build has no readable version, e.g. the bare binary.
    var currentVersion: ReleaseVersion? { AppBundle.shortVersion.flatMap(ReleaseVersion.init) }

    /// Checks if the user has asked for automatic checks and one is due. Silent either way.
    func checkIfDue() {
        guard preferences.checkForUpdatesAutomatically,
              UpdateCheckPolicy.isCheckDue(lastCheck: preferences.lastUpdateCheck, now: Date()) else { return }
        check(isManual: false)
    }

    /// Checks now, whatever the preference says. Used by the Check Now button.
    func checkNow() {
        check(isManual: true)
    }

    private func check(isManual: Bool) {
        guard task == nil else { return }
        guard let current = currentVersion else {
            // Without a version to compare against, any answer would be a guess.
            state = isManual ? .failed("This build has no version number to compare.") : .idle
            return
        }
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await fetch()
            task = nil
            preferences.lastUpdateCheck = Date()

            switch outcome {
            case let .success(release):
                if UpdateCheckPolicy.isUpdate(latest: release.version, current: current) {
                    state = .available(release)
                    AppLog.app.info("Update available: \(release.version.description, privacy: .public)")
                } else {
                    state = .upToDate(current)
                }
            case let .failure(message):
                // A background check that fails must not nag; only a manual one reports it.
                state = isManual ? .failed(message) : .idle
                AppLog.app.notice("Update check failed: \(message, privacy: .public)")
            }
        }
    }

    private enum Outcome {
        case success(Release)
        case failure(String)
    }

    private func fetch() async -> Outcome {
        do {
            let (data, response) = try await session.data(from: Self.endpoint)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failure("GitHub returned status \(http.statusCode).")
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let version = ReleaseVersion(payload.tagName) else {
                return .failure("Could not read the latest version number.")
            }
            guard let url = URL(string: payload.htmlURL) else {
                return .failure("The release has no valid link.")
            }
            return .success(Release(version: version, name: payload.name ?? version.description, url: url))
        } catch is CancellationError {
            return .failure("The check was cancelled.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private struct Payload: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }
}
