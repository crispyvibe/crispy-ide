import SwiftUI

// MARK: - Border Shape

enum CrispyVibesBorderShape: String, CaseIterable, Identifiable, Codable {
    case square
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: return "Square"
        case .rounded: return "Rounded"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .square: return 0
        case .rounded: return 8
        }
    }

    var buttonBorderShape: ButtonBorderShape {
        switch self {
        case .square: return .roundedRectangle(radius: 0)
        case .rounded: return .roundedRectangle(radius: 8)
        }
    }
}

// MARK: - Theme

struct CrispyVibesTheme: Equatable {
    var borderShape: CrispyVibesBorderShape
    var borderVisible: Bool
    var fontFamily: AppCodeFontFamily

    static let `default` = CrispyVibesTheme(
        borderShape: .rounded,
        borderVisible: true,
        fontFamily: .systemMonospaced
    )

    func containerShape(style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: borderShape.cornerRadius, style: style)
    }

    /// Returns 0 when square mode is active, otherwise the base radius.
    func radius(_ base: CGFloat) -> CGFloat {
        borderShape == .square ? 0 : base
    }
}

// MARK: - Container Border Modifier

struct CrispyVibesContainerBorderModifier: ViewModifier {
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.appThemePalette) private var palette
    var lineWidth: CGFloat = 1
    var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: theme.borderShape.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.borderShape.cornerRadius, style: .continuous)
                    .stroke(
                        palette.borderColorValue.opacity(theme.borderVisible ? opacity : 0),
                        lineWidth: lineWidth
                    )
            )
    }
}

extension View {
    func crispyvibesContainerBorder(lineWidth: CGFloat = 1, opacity: Double = 1.0) -> some View {
        modifier(CrispyVibesContainerBorderModifier(lineWidth: lineWidth, opacity: opacity))
    }
}
