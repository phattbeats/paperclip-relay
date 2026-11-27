import SwiftUI

/// Relay's visual language has two honest renderings:
///
/// - iOS 26+ uses the system's Liquid Glass. It is deliberately applied to
///   custom control surfaces only; navigation bars, toolbars and tab bars
///   already receive the correct system treatment and should not be wrapped
///   in a fake glass card.
/// - iOS 16–25 keeps the same hierarchy, spacing and contrast with a
///   material surface. The floor stays at iOS 16 for the installed phone.
///
/// The compiler guard matters as much as the availability check. CI's legacy
/// lane uses Xcode 16 / iOS 18 SDK to prove the fallback, and that compiler
/// cannot parse iOS 26-only SwiftUI symbols even inside `#available`.
struct RelayDesign {
    static let cardRadius: CGFloat = 20
    static let compactRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14

    static let background = LinearGradient(
        colors: [Color(uiColor: .systemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    /// A custom floating control surface which becomes Liquid Glass on iOS
    /// 26. Use this for banners, decision cards and compact summaries — not
    /// for every list row, where the system list material is clearer.
    func relayGlassCard(radius: CGFloat = RelayDesign.cardRadius) -> some View {
        modifier(RelayGlassCardModifier(radius: radius))
    }

    /// Consistent page background for the modern grouped-card hierarchy.
    func relayPageBackground() -> some View {
        background(RelayDesign.background.ignoresSafeArea())
    }
}

private struct RelayGlassCardModifier: ViewModifier {
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
