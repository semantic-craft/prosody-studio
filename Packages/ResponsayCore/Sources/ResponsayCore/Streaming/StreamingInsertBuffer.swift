import Foundation

/// 232 — accumulates streamed deltas append-only and tracks the full text so far.
///
/// The backend sends pure deltas, so `append` returns the delta as the text to insert now and
/// keeps the running `text` — the inserter inserts the returned suffix at the cursor, and uses
/// `text` for the end-of-stream accessibility verify + paste fallback (insert the full text if the
/// incremental keystrokes didn't land). Empty deltas are ignored so a stray keep-alive never posts
/// an empty keystroke.
public struct StreamingInsertBuffer: Sendable {
    /// The full text accumulated from every delta so far.
    public private(set) var text: String = ""

    public init() {}

    /// Append a streamed delta; returns the text to insert now (the delta, or "" if empty).
    @discardableResult
    public mutating func append(_ delta: String) -> String {
        guard !delta.isEmpty else { return "" }
        text += delta
        return delta
    }
}
