import Foundation

/// 146 — assembles word recognition + pitch contour feedback for one follow-read take.
public enum FollowReadFeedbackBuilder {
    public static func build(
        target: String,
        recognized: String,
        audioFileURL: URL,
        analysis: ProsodyAnalysis
    ) async -> SpeechFeedback {
        let wordFeedback = SpeechFeedbackEvaluator.evaluate(target: target, recognized: recognized)
        let pitch = await Task.detached(priority: .userInitiated) {
            pitchFeedback(audioFileURL: audioFileURL, analysis: analysis)
        }.value
        return wordFeedback.withPitchFeedback(pitch)
    }

    private static func pitchFeedback(
        audioFileURL: URL,
        analysis: ProsodyAnalysis
    ) -> PitchFeedback? {
        guard let learner = try? PitchContourExtractor.extract(fileURL: audioFileURL),
              learner.points.count >= 2
        else { return nil }
        let targetContour = PitchContourComparator.targetContour(from: analysis)
        return PitchContourComparator.evaluate(target: targetContour, learner: learner)
    }
}