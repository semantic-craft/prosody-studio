import Foundation

/// Result of a streaming text transform attempt, separated from the text itself so callers can
/// distinguish "safe to use one-shot fallback" from "streaming already touched the host field".
public enum StreamingTransformOutcome: Equatable, Sendable {
    case streamed(text: String)
    case unsupportedFallback(reason: String)
    case failed(reason: String, insertedText: String)

    public var insertedText: String? {
        switch self {
        case let .streamed(text):
            return text
        case .unsupportedFallback:
            return nil
        case let .failed(_, insertedText):
            return insertedText
        }
    }

    public var reason: String? {
        switch self {
        case .streamed:
            return nil
        case let .unsupportedFallback(reason), let .failed(reason, _):
            return reason
        }
    }
}
