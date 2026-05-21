import AppKit
import SwiftUI

/// Displays an SVG icon from Seti UI
struct SetiIconView: View {
    private struct IconAsset {
        let image: NSImage
        let shouldUseTemplateTint: Bool
    }

    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let iconName: String
    let size: CGFloat

    private static let imageCache = NSCache<NSString, NSImage>()
    private static let templateTintCache = NSCache<NSString, NSNumber>()
    private static let urlCache = NSCache<NSString, NSURL>()

    var body: some View {
        Group {
            if let iconAsset = Self.asset(named: iconName) {
                setiImageView(for: iconAsset)
            } else {
                Image(systemName: "doc.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
        .font(.system(size: uiScale.iconSize(size)))
        .frame(width: uiScale.iconSize(size), height: uiScale.iconSize(size))
    }

    @ViewBuilder
    private func setiImageView(for iconAsset: IconAsset) -> some View {
        if iconAsset.shouldUseTemplateTint {
            Image(nsImage: iconAsset.image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(appThemePalette.secondaryTextColor)
        } else {
            Image(nsImage: iconAsset.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private static func asset(named iconName: String) -> IconAsset? {
        let cacheKey = iconName as NSString
        let url: URL
        if let cachedURL = urlCache.object(forKey: cacheKey) as URL? {
            url = cachedURL
        } else {
            guard let resolvedURL = Bundle.main.url(
                forResource: iconName,
                withExtension: "svg",
                subdirectory: "SetiIcons"
            ) else {
                return nil
            }
            url = resolvedURL
            urlCache.setObject(resolvedURL as NSURL, forKey: cacheKey)
        }

        let image: NSImage
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            image = cachedImage
        } else {
            guard let loadedImage = NSImage(contentsOf: url) else {
                return nil
            }
            image = loadedImage
            imageCache.setObject(loadedImage, forKey: cacheKey)
        }

        let shouldUseTemplateTint: Bool
        if let cachedTintPreference = templateTintCache.object(forKey: cacheKey) {
            shouldUseTemplateTint = cachedTintPreference.boolValue
        } else {
            let usesTemplateTint = needsTemplateTint(for: url)
            templateTintCache.setObject(NSNumber(value: usesTemplateTint), forKey: cacheKey)
            shouldUseTemplateTint = usesTemplateTint
        }

        return IconAsset(image: image, shouldUseTemplateTint: shouldUseTemplateTint)
    }

    private static func needsTemplateTint(for url: URL) -> Bool {
        guard let svgMarkup = try? String(contentsOf: url, encoding: .utf8).lowercased() else {
            return false
        }

        let hasExplicitColorInstruction =
            svgMarkup.contains("fill=") ||
            svgMarkup.contains("stroke=") ||
            svgMarkup.contains("fill:") ||
            svgMarkup.contains("stroke:") ||
            svgMarkup.contains("currentcolor")

        return !hasExplicitColorInstruction
    }
}
