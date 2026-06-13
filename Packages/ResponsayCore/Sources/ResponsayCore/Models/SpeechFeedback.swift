import Foundation

public struct SpeechFeedback: Codable, Sendable, Equatable {
    public let targetText: String
    public let recognizedText: String
    public let similarity: Double
    public let message: String
    public let pitchFeedback: PitchFeedback?

    public init(
        targetText: String,
        recognizedText: String,
        similarity: Double,
        message: String,
        pitchFeedback: PitchFeedback? = nil
    ) {
        self.targetText = targetText
        self.recognizedText = recognizedText
        self.similarity = similarity
        self.message = message
        self.pitchFeedback = pitchFeedback
    }

    public func withPitchFeedback(_ pitchFeedback: PitchFeedback?) -> SpeechFeedback {
        SpeechFeedback(
            targetText: targetText,
            recognizedText: recognizedText,
            similarity: similarity,
            message: message,
            pitchFeedback: pitchFeedback)
    }
}
