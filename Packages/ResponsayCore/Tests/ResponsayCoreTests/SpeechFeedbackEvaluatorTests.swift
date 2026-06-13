import Testing
@testable import ResponsayCore

@Test func speechFeedbackEvaluator_exactMatch_scoresHigh() {
    let feedback = SpeechFeedbackEvaluator.evaluate(
        target: "I want to fix this bug.",
        recognized: "I want to fix this bug")

    #expect(feedback.similarity == 1)
    #expect(feedback.message == "识别文本很接近目标句。")
}

@Test func speechFeedbackEvaluator_partialMatch_flagsMissingWords() {
    let feedback = SpeechFeedbackEvaluator.evaluate(
        target: "I want to fix this bug.",
        recognized: "I want fix bug")

    #expect(feedback.similarity < 0.9)
    #expect(feedback.similarity > 0.4)
}

@Test func speechFeedbackEvaluator_emptyRecognition_isNotPhonemeScore() {
    let feedback = SpeechFeedbackEvaluator.evaluate(
        target: "I want to fix this bug.",
        recognized: "")

    #expect(feedback.similarity == 0)
    #expect(feedback.message == "没有识别到英文。")
}
