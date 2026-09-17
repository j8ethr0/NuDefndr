// NuDefndr - nudefndr.com
// Transparency Repository - In-app FAQ fetch and cache (v2.6.3)

import Foundation
import SwiftUI

enum FAQSite {
    static let host = "nudefndr.com"

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

    static func displayURL(for url: URL) -> String {
        host + url.path
    }
}

struct FAQDocument: Sendable {
    let html: String
    let fetched: Date
    var isCached: Bool = false
}

actor FAQDocumentStore {
    static let shared = FAQDocumentStore()

    enum LoadFailure: Error {
        case noDocument
    }

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
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15"]
        return URLSession(configuration: config)
    }()

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FAQ", isDirectory: true)
    }

    private func cacheFile(for url: URL) -> URL? {
        let name = url.path.split(separator: "/").joined(separator: "-")
        return cacheDirectory?.appendingPathComponent(name.isEmpty ? "faq.html" : name)
    }

    func cached(for url: URL) -> FAQDocument? {
        guard let file = cacheFile(for: url),
              let html = try? String(contentsOf: file, encoding: .utf8),
              !html.isEmpty else { return nil }
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return FAQDocument(html: html, fetched: date, isCached: true)
    }

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
        guard url.host == FAQSite.host else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func text(at url: URL) async -> String? {
        await bytes(at: url).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static let stylesheets = FAQPattern(#"<link[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["'][^>]*>"#)
    private static let scripts     = FAQPattern(#"<script[^>]*src=["']([^"']+)["'][^>]*>\s*</script>"#)
    private static let cssURLs     = FAQPattern(#"url\(['"]?([^'")]+)['"]?\)"#)
}

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

struct FAQAppearance: Sendable, Equatable {
    let ground: String
    let raised: String
    let seam: String
    let quiet: String
    let loud: String
    let accent: String
    let onAccent: String

    var styleTag: String {
        """
        <style>
          :root{--ground:\(ground);--raised:\(raised);--seam:\(seam);
                --quiet:\(quiet);--loud:\(loud);--accent:\(accent);--on-accent:\(onAccent);
                --rail:0}
          .strip,.foot,.skip,.band--accent{display:none!important}
          main>section.band:first-child{display:none!important}
          .exp__head:hover{background:transparent}
          body{background:var(--seam)}
          main{padding-bottom:2rem}
        </style>
        """
    }

    @MainActor
    static func current(theme: AppTheme, colorScheme: ColorScheme) -> FAQAppearance {
        let chrome = BandChrome.palette(theme: theme, colorScheme: colorScheme)
        let bands = BandPalette.resolve(theme: theme, colorScheme: colorScheme)
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
    func cssHex(in scheme: ColorScheme) -> String {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let onGround = { (c: CGFloat) in Int((min(max(c * a, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", onGround(r), onGround(g), onGround(b))
    }
}
