import Foundation

/// 232 — parses one line of the backend's downstream SSE into a `TextStreamEvent`.
///
/// The backend (`text_stream.mjs`) frames its stream as our own shape, NOT the provider's, so the
/// app never decodes vendor-specific chunks:
///   `data: {"delta":"…"}`   → `.delta`
///   `data: {"done":true}` / `data: [DONE]` → `.done`
///   `data: {"error":"…"}`   → `.failed`
/// Blank lines and `:` keep-alive comments are ignored. Pure — fully unit-tested without a server.
public struct SSELineParser: Sendable {
    public init() {}

    /// Map a single SSE line to an event, or `nil` for lines to ignore.
    public func event(for line: String) -> TextStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? String { return .failed(error) }
        if object["done"] as? Bool == true { return .done }
        if let delta = object["delta"] as? String, !delta.isEmpty { return .delta(delta) }
        return nil
    }

    /// Map a sequence of SSE lines to events, stopping at the first terminal (`.done`/`.failed`).
    /// This is the same line→event logic the live client delegates to, so it stands in for the
    /// client in tests where a real network stream isn't available.
    public func events(for lines: [String]) -> [TextStreamEvent] {
        var events: [TextStreamEvent] = []
        for line in lines {
            guard let event = event(for: line) else { continue }
            events.append(event)
            if case .delta = event { continue }
            break
        }
        return events
    }
}
