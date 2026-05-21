import SwiftUI

extension ContentView {
    var selectedAppearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreference) ?? .system
    }

    var resolvedColorScheme: ColorScheme {
        selectedAppearancePreference.colorScheme ?? systemColorScheme
    }

    var activeThemePalette: AppThemePalette {
        AppThemeResolver.palette(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: systemColorScheme,
            themePresetRaw: appThemePreset,
            customThemeJSON: appCustomThemePaletteJSON
        )
    }

    var preferredAppColorScheme: ColorScheme? {
        AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: systemColorScheme,
            themePresetRaw: appThemePreset,
            customThemeJSON: appCustomThemePaletteJSON
        )
    }

    var selectedProjectRailPosition: ProjectRailPosition {
        ProjectRailPosition(rawValue: defaultRailPositionRaw)
            ?? AppFirstRunExperience.Layout.defaultRailPosition
    }

    var selectedVibeSpaceCanvasMode: VibeSpaceCanvasMode {
        layoutPersistence.canvasMode(for: activeVibeSpaceID)
    }

    var selectedAppSideMenuDockPosition: AppSideMenuDockPosition {
        AppSideMenuDockPosition(rawValue: appSideMenuDockPositionRaw)
            ?? AppFirstRunExperience.AppSettings.sideMenuDockPosition
    }

    var resolvedAppSideMenuDockPosition: AppSideMenuDockPosition {
        if activeVibeSpaceID != nil,
           selectedVibeSpaceCanvasMode == .detailed,
           selectedProjectRailPosition == .right {
            return .left
        }
        return selectedAppSideMenuDockPosition
    }

    var canOpenProjectFilesFromAppMenu: Bool {
        !activeVibeSpaceSession.projects.isEmpty
    }

    var canOpenVibeSpaceSettingsFromAppMenu: Bool {
        activeVibeSpaceID != nil
    }

    var showsVibeSpaceSidebar: Bool {
        activeVibeSpaceID != nil &&
        !isPresentingSurface &&
        !isShowingHome &&
        isVibeSpaceSidebarVisible &&
        hasAnyVibeSpace
    }

    var shellPanelCornerRadii: RectangleCornerRadii {
        let r = themeManager.theme.radius(14)
        switch resolvedAppSideMenuDockPosition {
        case .left:
            return RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: r,
                topTrailing: r
            )
        case .right:
            return RectangleCornerRadii(
                topLeading: r,
                bottomLeading: r,
                bottomTrailing: 0,
                topTrailing: 0
            )
        }
    }

    var shellHeaderCornerRadii: RectangleCornerRadii {
        let r = themeManager.theme.radius(14)
        switch resolvedAppSideMenuDockPosition {
        case .left:
            return RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: r
            )
        case .right:
            return RectangleCornerRadii(
                topLeading: r,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 0
            )
        }
    }

    var contentPanelCornerRadii: RectangleCornerRadii {
        let r = themeManager.theme.radius(14)
        return RectangleCornerRadii(
            topLeading: r,
            bottomLeading: r,
            bottomTrailing: r,
            topTrailing: r
        )
    }

    var contentHeaderCornerRadii: RectangleCornerRadii {
        let r = themeManager.theme.radius(14)
        return RectangleCornerRadii(
            topLeading: r,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: r
        )
    }

    var clampedProjectRailWidth: CGFloat {
        switch selectedProjectRailPosition {
        case .left:
            return layoutPersistence.railSize(for: .left, vibespaceID: activeVibeSpaceID)
        case .right:
            return layoutPersistence.railSize(for: .right, vibespaceID: activeVibeSpaceID)
        case .top, .bottom:
            return 300
        }
    }

    var clampedProjectRailHeight: CGFloat {
        switch selectedProjectRailPosition {
        case .top:
            return layoutPersistence.railSize(for: .top, vibespaceID: activeVibeSpaceID)
        case .bottom:
            return layoutPersistence.railSize(for: .bottom, vibespaceID: activeVibeSpaceID)
        case .left, .right:
            return 250
        }
    }
}
