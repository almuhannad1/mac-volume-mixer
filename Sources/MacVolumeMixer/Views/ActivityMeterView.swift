import SwiftUI

/// A thin peak meter fed by real tap audio (never synthesized from the volume value).
struct ActivityMeterView: View {
    let level: MeterLevel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: proxy.size.width * CGFloat(level.value))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
