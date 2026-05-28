import Foundation

/// F049-v2: canonicalize browser URLs for comment-anchor stability.
///
/// Same logical page renders under many URL variations:
/// - tracking params (`utm_*`, `fbclid`, `gclid`, …)
/// - sensitive auth tokens (`token`, `access_token`, `session`, …)
/// - default ports (`:443`, `:80`)
/// - mixed-case scheme/host
/// - trailing slashes
///
/// The normalizer produces a stable string used as the `file_path` column
/// for `surfaceKind == .browser`. Idempotent: `normalize(normalize(x)) == normalize(x)`.
@MainActor
enum BrowserCommentURLNormalizer {

    /// Query parameter prefixes / names whose values are tracking, analytics,
    /// or session-bearing. Values are dropped during canonicalization.
    static let strippedQueryParams: Set<String> = [
        // Analytics
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_brand", "utm_creative", "utm_placement",
        "fbclid", "gclid", "dclid", "msclkid", "yclid",
        "mc_cid", "mc_eid",
        "_ga", "_gl",
        "ref", "ref_src", "ref_url",
        "igshid",
        // Auth / session — dropped to avoid persisting secrets in the DB
        "token", "access_token", "id_token", "refresh_token",
        "session", "session_id", "sid",
        "key", "api_key", "apikey",
        "auth", "authorization",
    ]

    /// Returns the canonical form of `url` for comment storage. Returns the
    /// raw input string if URL parsing fails (defensive — we never want to
    /// throw away the user's anchor target).
    static func canonicalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        // Lowercase scheme + host
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        // Strip default port
        if let scheme = components.scheme {
            if scheme == "http", components.port == 80 { components.port = nil }
            if scheme == "https", components.port == 443 { components.port = nil }
        }
        // Drop fragment — comment anchors target DOM elements, not #fragments
        components.fragment = nil
        // Strip tracking + sensitive query params
        if let items = components.queryItems {
            let kept = items.filter { item in
                !strippedQueryParams.contains(item.name.lowercased())
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        // Normalize trailing-slash on path: `/foo/` → `/foo` (except root `/`)
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    /// String overload for callers that hold a raw URL string.
    static func canonicalize(string raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return canonicalize(url)
    }
}
