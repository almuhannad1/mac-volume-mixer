import Observation

/// Calls `onChange` every time a property read inside `track` changes, for the lifetime of the app.
/// Bridges Observation into AppKit code that is not driven by SwiftUI.
@MainActor
func observeContinuously(
    _ track: @escaping @MainActor @Sendable () -> Void,
    onChange: @escaping @MainActor @Sendable () -> Void
) {
    withObservationTracking {
        track()
    } onChange: {
        Task { @MainActor in
            onChange()
            observeContinuously(track, onChange: onChange)
        }
    }
}
