import SwiftUI

struct AppIconView: View {
    let icon: AppIcon

    var body: some View {
        switch icon {
        case let .image(image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
