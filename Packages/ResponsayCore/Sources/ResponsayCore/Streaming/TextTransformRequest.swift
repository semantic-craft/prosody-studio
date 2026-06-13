import Foundation

/// The request shape for a streaming text transform (232 streaming-insert chain). Relocated
/// from the retired `StreamingTextTransformClient` (issue 360) so the live transport
/// `DirectStreamingTransformClient` and its caller `StreamingInsertionController` no longer
/// depend on a backend-shaped owner type.
public struct TextTransformRequest: Sendable {
    public var text: String
    /// polish | rewrite | translate | express (see `buildStreamingTransformPrompt`).
    public var mode: String
    public var targetLanguage: String?
    public var model: String?

    public init(
        text: String,
        mode: String = "polish",
        targetLanguage: String? = nil,
        model: String? = nil
    ) {
        self.text = text
        self.mode = mode
        self.targetLanguage = targetLanguage
        self.model = model
    }
}
