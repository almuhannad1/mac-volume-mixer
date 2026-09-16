import SwiftUI

struct ApplicationsSectionView: View {
    @Bindable var model: MixerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Applications")
                Spacer()
            }

            if model.showsSearchField {
                SearchField(text: $model.searchText, prompt: "Search applications")
            }

            let apps = model.visibleApps
            if model.controller.apps.isEmpty {
                EmptyStateView(
                    symbol: "speaker.zzz",
                    title: "No apps are using audio",
                    message: "Apps appear here as soon as they play sound."
                )
            } else if apps.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No results", message: "No application matches “\(model.searchText)”.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(apps) { app in
                        AppVolumeRow(
                            item: app,
                            icon: model.icon(for: app),
                            meter: model.meters.level(for: app.id),
                            onVolumeChange: { model.setVolume($0, for: app) },
                            onToggleMute: { model.toggleMute(for: app) },
                            onReset: { model.resetVolume(for: app) }
                        )
                        if app.id != apps.last?.id {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
