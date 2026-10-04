import SwiftUI

struct AboutSettingsView: View {
    private static let sponsorURL = URL(string: "https://github.com/sponsors/almuhannad1")!
    private static let profileURL = URL(string: "https://github.com/almuhannad1")!
    private static let repositoryURL = URL(string: "https://github.com/almuhannad1/mac-volume-mixer")!
    private static let contactEmail = "almuhannad226@gmail.com"

    var body: some View {
        Form {
            Section { appHeader }
            Section("Developer") { developer }
            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Audio engine", value: "Core Audio process taps")
                LabeledContent("Source") {
                    Link("github.com/almuhannad1/mac-volume-mixer", destination: Self.repositoryURL)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Volume Mixer").font(.title3.weight(.semibold))
                Text("Per-application volume for macOS").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var developer: some View {
        Group {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15))
                    Image(systemName: "person.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("almuhannad1").font(.system(size: 13, weight: .semibold))
                    Text("Independent developer").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            LabeledContent("GitHub") {
                Link("github.com/almuhannad1", destination: Self.profileURL)
            }
            LabeledContent("Contact") {
                Link(Self.contactEmail, destination: URL(string: "mailto:\(Self.contactEmail)")!)
            }

            HStack(spacing: 10) {
                Link(destination: Self.sponsorURL) {
                    Label("Sponsor", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .accessibilityLabel("Sponsor this project on GitHub")
                Text("Support continued development of this app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private static var version: String {
        let short = AppBundle.shortVersion ?? "development build"
        guard let build = AppBundle.buildVersion else { return short }
        return "\(short) (\(build))"
    }
}
