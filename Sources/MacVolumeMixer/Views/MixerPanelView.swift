import SwiftUI

/// Root view of the menu bar popover.
struct MixerPanelView: View {
    @Bindable var model: MixerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FittedScrollView(maxHeight: 520, contentHeight: $model.panelContentHeight) {
                VStack(alignment: .leading, spacing: 14) {
                    OutputSectionView(model: model)
                    if let notice = model.captureNotice {
                        PermissionBannerView(notice: notice, onOpenSettings: model.openPrivacySettings, onRetry: model.recheckPermission)
                    }
                    ApplicationsSectionView(model: model)
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Mac Volume Mixer")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        HStack {
            Button(action: model.openSettings) {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit", action: model.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A scroll view that is exactly as tall as its content, up to `maxHeight`, so the popover
/// shrinks for short lists and scrolls for long ones.
struct FittedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @Binding var contentHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            MainActor.assumeIsolated { contentHeight = height }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
