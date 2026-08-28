// NuDefndr — nudefndr.com
// Transparency Repository - In-app FAQ fetch and cache (v2.6.1)

import Foundation
import SwiftUI

enum FAQSite {
    static let host = "nudefndr.com"

    /// The page for the localization the app is actually running in.
    ///
    /// `preferredLocalizations` rather than `Locale.current`: it is the language
    /// the rest of the UI resolved to, so the FAQ cannot come back in a language
    /// the app is not speaking. The site has ja/th/zh and English; anything else
    /// falls back to English, which is also what the string catalog does.
    static func pageURL(for localizations: [String] = Bundle.main.preferredLocalizations) -> URL {
        let code = (localizations.first ?? "en").prefix(2).lowercased()
        let path: String
        switch code {
        case "ja": path = "ja/faq.html"
        case "th": path = "th/faq.html"
        case "zh": path = "zh/faq.html"
        default:   path = "faq.html"
        }
        return URL(string: "https://\(host)/\(path)")!
    }

    /// What the screen shows the user about where this came from. Not a link —
    /// the point is that they can check it from somewhere else if they want to.
    static func displayURL(for url: URL) -> String {
        host + url.path
    }
}

/// One fetched-and-inlined copy of the FAQ.
struct FAQDocument: Sendable {
    let html: String
    let fetched: Date
    /// True when the network failed and this came off disk.
    var isCached: Bool = false
}

/// Fetches, inlines and caches the FAQ page.
actor FAQDocumentStore {
    static let shared = FAQDocumentStore()

    enum LoadFailure: Error {
        /// Nothing on the network and nothing on disk. The only state that has to
        /// draw an error.
        case noDocument
    }

    /// Ephemeral, and every switch that could leave a trace is off.
    ///
    /// No cookie storage, no credential storage, no URL cache — the only thing
    /// that persists between launches is the snapshot this actor writes itself,
    /// which is a public page with nothing user-specific in it.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // The default is the app's own UA string, which names the app and its
        // build to the server. The FAQ does not need to know either.
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15"]
        return URLSession(configuration: config)
    }()

    /// `Caches`, not `Application Support`: iOS is free to reclaim it, the app
    /// simply refetches, and it is excluded from backups without asking.
    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FAQ", isDirectory: true)
    }

    private func cacheFile(for url: URL) -> URL? {
        let name = url.path.split(separator: "/").joined(separator: "-")
        return cacheDirectory?.appendingPathComponent(name.isEmpty ? "faq.html" : name)
    }

    /// The cached snapshot, if there is one. Cheap, and the screen shows it
    /// before it starts asking the network for a newer one.
    func cached(for url: URL) -> FAQDocument? {
        guard let file = cacheFile(for: url),
              let html = try? String(contentsOf: file, encoding: .utf8),
              !html.isEmpty else { return nil }
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return FAQDocument(html: html, fetched: date, isCached: true)
    }

    /// Fetch, inline, cache and return. Throws only when there is also no cache.
    func load(url: URL, appearance: FAQAppearance) async throws -> FAQDocument {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let page = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let html = await inlined(page, base: url, appearance: appearance)
            write(html, for: url)
            return FAQDocument(html: html, fetched: Date())
        } catch {
            if let cached = cached(for: url) { return cached }
            throw LoadFailure.noDocument
        }
    }

    private func write(_ html: String, for url: URL) {
        guard let dir = cacheDirectory, let file = cacheFile(for: url) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? html.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Inlining

    /// Pull the page's own stylesheet, script and web font into the file.
    ///
    /// Best effort by design: a subresource that will not fetch is left as the
    /// original tag, which with `baseURL: nil` simply does not load. A missing
    /// stylesheet costs the page its styling and keeps every word of it — an
    /// acceptable floor, and one that never happens while the network is up.
    private func inlined(_ page: String, base: URL, appearance: FAQAppearance) async -> String {
        var html = page

        for match in Self.stylesheets.matches(in: html) {
            guard let href = match.capture(1, in: html),
                  let cssURL = URL(string: href, relativeTo: base),
                  var css = await text(at: cssURL) else { continue }
            css = await inliningFontURLs(css, base: cssURL)
            html = html.replacingOccurrences(of: match.text, with: "<style>\(css)</style>")
        }

        for match in Self.scripts.matches(in: html) {
            guard let src = match.capture(1, in: html),
                  let jsURL = URL(string: src, relativeTo: base),
                  let js = await text(at: jsURL) else { continue }
            html = html.replacingOccurrences(of: match.text, with: "<script>\(js)</script>")
        }

        return html.replacingOccurrences(of: "</head>", with: appearance.styleTag + "</head>")
    }

    /// `url('jetbrains-mono-latin.woff2')` → a `data:` URI, so the face survives
    /// with no network. ~40 KB of font becomes ~54 KB of base64; the whole
    /// snapshot lands around 90 KB.
    private func inliningFontURLs(_ css: String, base: URL) async -> String {
        var css = css
        for match in Self.cssURLs.matches(in: css) {
            guard let ref = match.capture(1, in: css),
                  !ref.hasPrefix("data:"),
                  let assetURL = URL(string: ref, relativeTo: base),
                  let data = await bytes(at: assetURL) else { continue }
            let mime = assetURL.pathExtension == "woff2" ? "font/woff2" : "application/octet-stream"
            let encoded = "url('data:\(mime);base64,\(data.base64EncodedString())')"
            css = css.replacingOccurrences(of: match.text, with: encoded)
        }
        return css
    }

    private func bytes(at url: URL) async -> Data? {
        guard url.host == FAQSite.host else { return nil }   // same-origin only
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func text(at url: URL) async -> String? {
        await bytes(at: url).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Patterns

    private static let stylesheets = FAQPattern(#"<link[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["'][^>]*>"#)
    private static let scripts     = FAQPattern(#"<script[^>]*src=["']([^"']+)["'][^>]*>\s*</script>"#)
    private static let cssURLs     = FAQPattern(#"url\(['"]?([^'")]+)['"]?\)"#)
}

// MARK: - Regex plumbing

/// A named wrapper so the call sites above read as intent rather than as
/// `NSRegularExpression` bookkeeping.
private struct FAQPattern {
    struct Match {
        let text: String
        private let result: NSTextCheckingResult
        private let source: String

        init(result: NSTextCheckingResult, source: String) {
            self.result = result
            self.source = source
            self.text = (source as NSString).substring(with: result.range)
        }

        func capture(_ index: Int, in _: String) -> String? {
            guard index < result.numberOfRanges,
                  let range = Range(result.range(at: index), in: source) else { return nil }
            return String(source[range])
        }
    }

    private let regex: NSRegularExpression?

    init(_ pattern: String) {
        regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    func matches(in source: String) -> [Match] {
        guard let regex else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).map { Match(result: $0, source: source) }
    }
}

// MARK: - Appearance

/// The running theme, as the six custom properties the site's stylesheet is
/// built on.
///
/// The site is MNML and only MNML — `styles/mnml.css` hard-codes `#121212` and
/// `#ff4d00` — which is right on the web and wrong inside an app the user has
/// put in Cyber, or in Essential on a white morning. Overriding the variables
/// re-skins the whole page without touching a single rule in it.
struct FAQAppearance: Sendable, Equatable {
    let ground: String
    let raised: String
    let seam: String
    let quiet: String
    let loud: String
    let accent: String
    let onAccent: String

    /// Injected last, so it wins over the stylesheet it follows.
    ///
    /// The site chrome goes with it: inside the app the header is the app's, and
    /// a second nav bar offering About / Vault / Download is both redundant and
    /// unreachable — `baseURL` is nil, so those links resolve to nothing.
    var styleTag: String {
        """
        <style>
          :root{--ground:\(ground);--raised:\(raised);--seam:\(seam);
                --quiet:\(quiet);--loud:\(loud);--accent:\(accent);--on-accent:\(onAccent);
                /* The site draws a coloured rail down the left of every band.
                   Zeroed inside the app, which also pulls the text back onto the
                   app's own margin — the padding is `calc(margin + rail)`. */
                --rail:0}
          .strip,.foot,.skip,.band--accent{display:none!important}
          /* The page's own FAQ / ANSWERED title. The app header two lines above
             it already says FAQ, and a screen does not need two. */
          main>section.band:first-child{display:none!important}
          /* No hover state on a touch screen — it sticks after a tap and leaves
             one question looking selected. */
          .exp__head:hover{background:transparent}
          body{background:var(--seam)}
          /* Inside a sheet on a phone, not a browser window. */
          main{padding-bottom:2rem}
        </style>
        """
    }

    @MainActor
    static func current(theme: AppTheme, colorScheme: ColorScheme) -> FAQAppearance {
        let chrome = BandChrome.palette(theme: theme, colorScheme: colorScheme)
        let bands = BandPalette.resolve(theme: theme, colorScheme: colorScheme)
        // `primaryAccent`. MNML's `secondaryAccent(for:)` is `MnmlPalette.quiet`,
        // a grey — the theme deliberately has no second accent — so mapping the
        // site's `--accent` to it drained every heading and every pixel headline
        // on the page to grey. Same call `VaultHealthSheet` makes, same reason.
        let accent = theme.primaryAccent(for: colorScheme)
        return FAQAppearance(
            ground: chrome.ground.cssHex(in: colorScheme),
            raised: chrome.raised.cssHex(in: colorScheme),
            seam: chrome.seam.cssHex(in: colorScheme),
            quiet: chrome.quiet.cssHex(in: colorScheme),
            loud: theme.textPrimary(for: colorScheme).cssHex(in: colorScheme),
            accent: accent.cssHex(in: colorScheme),
            onAccent: bands.ink(on: accent).cssHex(in: colorScheme)
        )
    }
}

extension Color {
    /// `#rrggbb`, resolved against a scheme.
    ///
    /// Resolved explicitly: half the palette is dynamic, and asking a dynamic
    /// `UIColor` for its components without traits gives whatever the process
    /// default happens to be — which on a dark-forcing theme is the wrong half.
    func cssHex(in scheme: ColorScheme) -> String {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Flattened onto the ground rather than carried through: CSS custom
        // properties here are used as solid fills, and a translucent one (Pixel's
        // half-black wash) would otherwise show the page's black through it.
        let onGround = { (c: CGFloat) in Int((min(max(c * a, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", onGround(r), onGround(g), onGround(b))
    }
}
