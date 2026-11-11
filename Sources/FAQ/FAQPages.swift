// NuDefndr - nudefndr.com
// Transparency Repository - In-app FAQ, read from the app bundle (v2.6.8)

import Foundation
import SwiftUI

enum FAQPages {
    static func resourceName(for localizations: [String] = Bundle.main.preferredLocalizations) -> String {
        switch (localizations.first ?? "en").prefix(2).lowercased() {
        case "ja": return "faq-ja"
        case "th": return "faq-th"
        case "zh": return "faq-zh"
        default:   return "faq-en"
        }
    }

    @MainActor
    static func html(appearance: FAQAppearance,
                     localizations: [String] = Bundle.main.preferredLocalizations) -> String? {
        let name = resourceName(for: localizations)
        guard let page = pages[name] ?? load(name) else {
            assertionFailure("FAQ page missing from the app bundle")
            return nil
        }
        pages[name] = page
        return page.replacingOccurrences(of: "</head>", with: appearance.styleTag + "</head>")
    }

    @MainActor private static var pages: [String: String] = [:]

    private static func load(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "html") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
