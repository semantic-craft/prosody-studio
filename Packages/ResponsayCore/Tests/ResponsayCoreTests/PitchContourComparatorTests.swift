import Testing
@testable import ResponsayCore

@Test func pitchContourComparator_scoresSimilarContoursHigh() {
    let feedback = PitchContourComparator.evaluate(
        target: PitchContour(points: [120, 140, 165, 180]),
        learner: PitchContour(points: [118, 142, 160, 176]))

    #expect(feedback.similarity > 0.9)
    #expect(feedback.targetTrend == "rise")
    #expect(feedback.learnerTrend == "rise")
}

@Test func pitchContourComparator_flagsOppositeTrend() {
    let feedback = PitchContourComparator.evaluate(
        target: PitchContour(points: [180, 160, 140, 120]),
        learner: PitchContour(points: [120, 140, 160, 180]))

    #expect(feedback.similarity < 0.6)
    #expect(feedback.targetTrend == "fall")
    #expect(feedback.learnerTrend == "rise")
}

@Test func pitchContourComparator_buildsTargetContourFromProsodyTone() {
    let analysis = ProsodyAnalysis(
        text: "Are you sure",
        isGeneratedExample: false,
        sourceWord: nil,
        ipa: "/ɑr ju ʃʊr/",
        thoughtGroups: [
            ThoughtGroup(tone: .rise, words: [
                Word(text: "Are", syllables: ["Are"], stressIndex: nil,
                     stressed: false, nuclear: false, ipa: nil, linkToNext: nil),
                Word(text: "you", syllables: ["you"], stressIndex: nil,
                     stressed: false, nuclear: false, ipa: nil, linkToNext: nil),
                Word(text: "sure", syllables: ["sure"], stressIndex: 0,
                     stressed: true, nuclear: true, ipa: nil, linkToNext: nil),
            ]),
        ],
        notes: nil)

    let contour = PitchContourComparator.targetContour(from: analysis)

    #expect(contour.points.count == 3)
    #expect((contour.points.first ?? 1) < (contour.points.last ?? 0))
}
