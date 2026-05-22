import Foundation

/// Channel for Crispy auto-updates. Maps to the Sparkle appcast feed URL.
///
/// - `stable`: Only promoted releases. Recommended for most users.
/// - `dev`: Every build. May be unstable; for insiders/preview.
/// - `custom`: User-supplied feed URL.
enum AppUpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case dev
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .dev: return "Dev"
        case .custom: return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .stable: return "Only promoted releases. Recommended."
        case .dev: return "Every build. May be unstable."
        case .custom: return "Manually specify a feed URL."
        }
    }

    /// The Sparkle appcast feed URL for built-in channels. `nil` for `.custom`.
    var feedURL: String? {
        switch self {
        case .stable: return Self.stableFeedURL
        case .dev: return Self.devFeedURL
        case .custom: return nil
        }
    }

    static let stableFeedURL = "https://crispyvibe.com/updates/macos/stable/appcast.xml"
    static let devFeedURL = "https://crispyvibe.com/updates/macos/dev/appcast.xml"

    /// Infer the channel from a stored feed URL. Used to migrate users from the
    /// old "edit URL directly" setting to the new channel picker.
    ///
    /// - Returns: `.stable` or `.dev` if the URL exactly matches a known channel
    ///   feed, otherwise `.custom`.
    static func inferred(fromFeedURL feedURL: String?) -> AppUpdateChannel {
        let trimmed = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed == stableFeedURL { return .stable }
        if trimmed == devFeedURL { return .dev }
        return .custom
    }
}
