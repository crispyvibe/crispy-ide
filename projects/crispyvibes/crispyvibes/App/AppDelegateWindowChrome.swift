import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func applyBundleConfiguredApplicationIcon() {
        guard applicationIconImageNeedsFallback else { return }

        if let iconName = iconNameFromBundleInfo(),
           let iconImage = NSImage(named: NSImage.Name(iconName)) {
            NSApp.applicationIconImage = iconImage
            return
        }

        guard let iconFile = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              !iconFile.isEmpty else { return }
        if let iconURL = iconURLForBundleIconFile(iconFile),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }

    func applyWindowChromeToAllWindows() {
        let theme = resolvedThemePaletteForCurrentAppearance()
        let appearanceName: NSAppearance.Name = theme.prefersDarkWindowChrome ? .darkAqua : .aqua
        if NSApp.appearance?.name != appearanceName {
            NSApp.appearance = NSAppearance(named: appearanceName)
        }
        for window in NSApp.windows {
            applyWindowChrome(to: window)
        }
    }

    func applyWindowChrome(to window: NSWindow) {
        guard !(window is NSPanel) else { return }

        let theme = resolvedThemePaletteForCurrentAppearance()
        let shouldAllowBackgroundDragging = Self.windowBackgroundDraggingAllowed(
            prefersDarkWindowChrome: theme.prefersDarkWindowChrome
        )
        // Keep titlebar/toolbar geometry stable across light and dark appearances.
        // This prevents toolbar controls from jumping between leading/trailing positions.
        if window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.remove(.fullSizeContentView)
        }
        // Flatten chrome so the titlebar can use the theme's chrome base token.
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }
        if window.isMovableByWindowBackground != shouldAllowBackgroundDragging {
            window.isMovableByWindowBackground = shouldAllowBackgroundDragging
        }
        window.backgroundColor = theme.nsWindowBackgroundColor
        if window.toolbar?.showsBaselineSeparator == true {
            window.toolbar?.showsBaselineSeparator = false
        }
        ensureCenteredTitlebarBranding(for: window)
        window.contentView?.superview?.layer?.backgroundColor = nil
    }

    func ensureCenteredTitlebarBranding(for window: NSWindow) {
        guard window.toolbar != nil,
              let titlebarContainer = window.standardWindowButton(.closeButton)?.superview else { return }

        let existingBrandingView = titlebarContainer.subviews.first {
            $0.identifier == brandingAccessoryIdentifier
        }
        existingBrandingView?.removeFromSuperview()

        let brandingView = makeCenteredBrandingView()
        brandingView.translatesAutoresizingMaskIntoConstraints = false
        brandingView.identifier = brandingAccessoryIdentifier
        titlebarContainer.addSubview(brandingView)

        NSLayoutConstraint.activate([
            brandingView.centerXAnchor.constraint(equalTo: titlebarContainer.centerXAnchor),
            brandingView.centerYAnchor.constraint(equalTo: titlebarContainer.centerYAnchor),
            brandingView.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarContainer.leadingAnchor, constant: 92),
            brandingView.trailingAnchor.constraint(lessThanOrEqualTo: titlebarContainer.trailingAnchor, constant: -92)
        ])
    }

    func makeCenteredBrandingView() -> NSView {
        let uiScale = CrispyVibesUIScale.current()
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 2.75
        iconView.layer?.masksToBounds = true

        let titleButton = NSButton(title: "crispyvibe.com", target: nil, action: #selector(AppDelegate.openWebsite))
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.isBordered = false
        titleButton.font = NSFont.systemFont(ofSize: uiScale.textSize(12), weight: .medium)
        titleButton.contentTintColor = .labelColor

        let stackView = NSStackView(views: [iconView, titleButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = uiScale.spacing(5)
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: uiScale.iconSize(15)),
            iconView.heightAnchor.constraint(equalToConstant: uiScale.iconSize(15)),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: uiScale.chromeSize(17))
        ])

        return container
    }

    static func windowBackgroundDraggingAllowed(prefersDarkWindowChrome: Bool) -> Bool {
        false
    }

    func resolvedThemePaletteForCurrentAppearance() -> AppThemePalette {
        let defaults = UserDefaults.standard
        let systemScheme: ColorScheme =
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light

        return AppThemeResolver.palette(
            appearancePreferenceRaw: defaults.string(forKey: AppPreferences.appearancePreferenceKey)
                ?? AppPreferences.defaultAppearancePreference,
            fallbackSystemColorScheme: systemScheme,
            themePresetRaw: defaults.string(forKey: AppPreferences.appThemePresetKey)
                ?? AppPreferences.defaultAppThemePreset,
            customThemeJSON: defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
                ?? ""
        )
    }

    private func iconNameFromBundleInfo() -> String? {
        guard let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String else {
            return nil
        }
        let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var applicationIconImageNeedsFallback: Bool {
        guard let iconImage = NSApp.applicationIconImage else { return true }
        return !iconImage.isValid || iconImage.size.width <= 0 || iconImage.size.height <= 0
    }

    private func iconURLForBundleIconFile(_ iconFile: String) -> URL? {
        let fileExtension = (iconFile as NSString).pathExtension
        if fileExtension.isEmpty {
            return Bundle.main.url(forResource: iconFile, withExtension: nil)
                ?? Bundle.main.url(forResource: iconFile, withExtension: "icns")
        }
        let baseName = (iconFile as NSString).deletingPathExtension
        return Bundle.main.url(forResource: baseName, withExtension: fileExtension)
            ?? Bundle.main.url(forResource: iconFile, withExtension: nil)
    }
}
