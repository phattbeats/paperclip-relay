import SwiftUI

/// The app-wide notice surface.
///
/// It used to be an overlay pinned to the top of the window, which meant it
/// painted over the navigation bar and the issue controls underneath it. The
/// banner is now inserted as a top safe-area inset on each screen, so it has
/// its own space and pushes the content down instead of covering it.
struct RelayBannerView: View {
    @EnvironmentObject private var board: BoardStore

    var body: some View {
        if let banner = board.banner {
            HStack(spacing: 8) {
                Image(systemName: board.bannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(board.bannerIsError ? Color.orange : Color.green)
                Text(banner)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    board.banner = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .relayGlassCard(radius: RelayDesign.compactRadius)
            .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// Give the banner its own space at the top of this screen, below the
    /// navigation bar. Applied to the content of every screen so the toast
    /// never overlaps the controls underneath it.
    func relayBannerInset() -> some View {
        modifier(RelayBannerInsetModifier())
    }
}

private struct RelayBannerInsetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            RelayBannerView()
        }
    }
}
