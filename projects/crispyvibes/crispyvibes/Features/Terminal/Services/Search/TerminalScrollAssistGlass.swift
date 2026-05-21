import SwiftUI

/// View modifier that applies Liquid Glass.
///
/// Originally introduced for the scroll assist overlay (F046); now used widely
/// throughout the app wherever glass is appropriate.
extension View {
    func scrollAssistGlassBackground<S: Shape>(in shape: S) -> some View {
        self.glassEffect(in: shape)
    }
}

/// Container view that wraps content in a `GlassEffectContainer` so adjacent
/// glass elements compose cohesively (morphing animation, no double-sampling).
struct ScrollAssistGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}
