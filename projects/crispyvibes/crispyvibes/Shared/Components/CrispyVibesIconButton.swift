import SwiftUI

enum CrispyVibesIconButtonVariant {
    case compact
    case card
    case panel

    var baseSymbolSize: CGFloat {
        switch self {
        case .compact:
            10
        case .card:
            12
        case .panel:
            12
        }
    }

    var basePadding: CGFloat {
        switch self {
        case .compact:
            4
        case .card:
            6
        case .panel:
            8
        }
    }
}

enum CrispyVibesHeaderStyle {
    case panel
    case card
    case compact

    var baseMinHeight: CGFloat {
        switch self {
        case .panel:
            36
        case .card:
            32
        case .compact:
            28
        }
    }

    var baseHorizontalPadding: CGFloat {
        switch self {
        case .panel:
            12
        case .card:
            8
        case .compact:
            8
        }
    }

    var baseVerticalPadding: CGFloat {
        switch self {
        case .panel:
            6
        case .card:
            5
        case .compact:
            4
        }
    }

    var baseSpacing: CGFloat {
        switch self {
        case .panel:
            8
        case .card:
            8
        case .compact:
            6
        }
    }

    func minHeight(scale: CGFloat) -> CGFloat {
        round(baseMinHeight * scale)
    }

    func horizontalPadding(scale: CGFloat) -> CGFloat {
        round(baseHorizontalPadding * scale)
    }

    func verticalPadding(scale: CGFloat) -> CGFloat {
        round(baseVerticalPadding * scale)
    }

    func spacing(scale: CGFloat) -> CGFloat {
        round(baseSpacing * scale)
    }

    func titleFont(scale: CGFloat) -> Font {
        let textScale = CrispyVibesUIScale.current().textScale
        switch self {
        case .panel:
            return Font.system(size: 13 * textScale, weight: .semibold)
        case .card:
            return Font.system(size: 12 * textScale, weight: .semibold)
        case .compact:
            return Font.system(size: 11 * textScale, weight: .semibold)
        }
    }

    func detailFont(scale: CGFloat) -> Font {
        let textScale = CrispyVibesUIScale.current().textScale
        switch self {
        case .panel:
            return Font.system(size: 12 * textScale)
        case .card:
            return Font.system(size: 11 * textScale)
        case .compact:
            return Font.system(size: 11 * textScale)
        }
    }

    func badgeFont(scale: CGFloat) -> Font {
        let textScale = CrispyVibesUIScale.current().textScale
        switch self {
        case .panel:
            return Font.system(size: 11 * textScale, weight: .semibold)
        case .card:
            return Font.system(size: 11 * textScale, weight: .semibold)
        case .compact:
            return Font.system(size: 11 * textScale, weight: .semibold)
        }
    }

    var actionButtonVariant: CrispyVibesIconButtonVariant {
        switch self {
        case .panel:
            .panel
        case .card:
            .card
        case .compact:
            .compact
        }
    }
}

struct CrispyVibesIconButton: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let systemName: String
    var size: CGFloat = 14
    var padding: CGFloat = 6
    var color: Color? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    init(
        systemName: String,
        size: CGFloat = 14,
        padding: CGFloat = 6,
        color: Color? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.padding = padding
        self.color = color
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    init(
        systemName: String,
        variant: CrispyVibesIconButtonVariant,
        color: Color? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            systemName: systemName,
            size: variant.baseSymbolSize,
            padding: variant.basePadding,
            color: color,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    private var chromeScale: CGFloat {
        uiScale.chromeScale
    }

    private var resolvedSize: CGFloat {
        uiScale.iconSize(size)
    }

    private var resolvedPadding: CGFloat {
        round(padding * chromeScale)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: resolvedSize))
                .foregroundStyle(color ?? .primary)
                .frame(
                    width: resolvedSize + resolvedPadding * 2,
                    height: resolvedSize + resolvedPadding * 2
                )
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct CrispyVibesHeaderBadge: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let text: String
    let style: CrispyVibesHeaderStyle
    var tint: Color? = nil
    var emphasis: Double = 0.16

    private var chromeScale: CGFloat {
        uiScale.chromeScale
    }

    var body: some View {
        let resolvedTint = tint ?? appThemePalette.secondaryTextColor

        Text(text)
            .font(style.badgeFont(scale: chromeScale))
            .foregroundStyle(resolvedTint)
            .padding(.horizontal, round((style == .panel ? 7 : 6) * chromeScale))
            .padding(.vertical, round((style == .panel ? 3 : 2) * chromeScale))
            .background(resolvedTint.opacity(emphasis))
            .clipShape(Capsule())
    }
}

struct CrispyVibesHeaderChrome<Content: View>: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let style: CrispyVibesHeaderStyle
    let verticalAlignment: VerticalAlignment
    var background: Color? = nil
    var cornerRadii: RectangleCornerRadii? = nil
    let content: Content

    init(
        style: CrispyVibesHeaderStyle,
        verticalAlignment: VerticalAlignment = .center,
        background: Color? = nil,
        cornerRadii: RectangleCornerRadii? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.verticalAlignment = verticalAlignment
        self.background = background
        self.cornerRadii = cornerRadii
        self.content = content()
    }

    private var chromeScale: CGFloat {
        uiScale.chromeScale
    }

    var body: some View {
        let base = HStack(alignment: verticalAlignment, spacing: style.spacing(scale: chromeScale)) {
            content
        }
        .padding(.horizontal, style.horizontalPadding(scale: chromeScale))
        .padding(.vertical, style.verticalPadding(scale: chromeScale))
        .frame(maxWidth: .infinity, minHeight: style.minHeight(scale: chromeScale), alignment: .leading)

        if let background {
            if let cornerRadii {
                base
                    .background(background)
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: cornerRadii,
                            style: .continuous
                        )
                    )
            } else {
                base.background(background)
            }
        } else {
            base
        }
    }
}
