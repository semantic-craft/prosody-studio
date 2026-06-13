import Foundation

public struct ExpressionContext: Codable, Sendable, Equatable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var selectedText: String?
    public var textBeforeCursor: String?
    public var textAfterCursor: String?
    public var browserURLHost: String?
    public var hotwords: [String]

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        selectedText: String? = nil,
        textBeforeCursor: String? = nil,
        textAfterCursor: String? = nil,
        browserURL: String? = nil,
        hotwords: [String] = []
    ) {
        self.appName = Self.clean(appName, limit: 120)
        self.bundleIdentifier = Self.clean(bundleIdentifier, limit: 120)
        self.windowTitle = Self.clean(windowTitle, limit: 180)
        self.selectedText = Self.clean(selectedText, limit: 700)
        self.textBeforeCursor = Self.clean(textBeforeCursor, limit: 700)
        self.textAfterCursor = Self.clean(textAfterCursor, limit: 700)
        self.browserURLHost = Self.cleanBrowserURLHost(browserURL)
        self.hotwords = Self.cleanHotwords(hotwords)
    }

    public func withBrowserURL(_ browserURL: String?) -> ExpressionContext {
        var copy = self
        copy.browserURLHost = Self.cleanBrowserURLHost(browserURL)
        return copy
    }

    public var isEmpty: Bool {
        appName == nil
            && bundleIdentifier == nil
            && windowTitle == nil
            && selectedText == nil
            && textBeforeCursor == nil
            && textAfterCursor == nil
            && browserURLHost == nil
            && hotwords.isEmpty
    }

    var jsonObject: [String: Any] {
        var object = [String: Any]()
        if let appName { object["appName"] = appName }
        if let bundleIdentifier { object["bundleIdentifier"] = bundleIdentifier }
        if let windowTitle { object["windowTitle"] = windowTitle }
        if let selectedText { object["selectedText"] = selectedText }
        if let textBeforeCursor { object["textBeforeCursor"] = textBeforeCursor }
        if let textAfterCursor { object["textAfterCursor"] = textAfterCursor }
        // Browser URL is kept as a deterministic legal-routing signal only. It
        // is intentionally omitted from generic LLM context payloads.
        if !hotwords.isEmpty { object["hotwords"] = hotwords }
        return object
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return String(raw.prefix(limit))
    }

    private static func cleanBrowserURLHost(_ value: String?) -> String? {
        guard let value else { return nil }
        return BrowserURLClassifier.host(from: value)
    }

    private static func cleanHotwords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned = [String]()
        for value in values {
            guard let word = clean(value, limit: 80), !seen.contains(word) else { continue }
            cleaned.append(word)
            seen.insert(word)
            if cleaned.count == 40 { break }
        }
        return cleaned
    }
}
