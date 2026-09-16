import MixerCore
import Observation

/// One row's displayed audio level. Separate observable objects mean a meter update only
/// re-renders its own row.
@MainActor
@Observable
final class MeterLevel {
    fileprivate(set) var value: Float = 0
}

@MainActor
final class MeterBank {
    private var levels: [String: MeterLevel] = [:]

    func level(for appID: String) -> MeterLevel {
        if let level = levels[appID] { return level }
        let level = MeterLevel()
        levels[appID] = level
        return level
    }

    func update(appID: String, peak: Float?) {
        let level = level(for: appID)
        let target = peak.map(MeterScale.level(forPeak:)) ?? 0
        let next = MeterScale.decayed(previous: level.value, target: target)
        if next != level.value {
            level.value = next
        }
    }

    func prune(keeping appIDs: Set<String>) {
        levels = levels.filter { appIDs.contains($0.key) }
    }
}
