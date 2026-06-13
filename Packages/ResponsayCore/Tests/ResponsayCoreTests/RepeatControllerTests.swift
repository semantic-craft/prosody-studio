import Testing
@testable import ResponsayCore

private let repeatSentences = [
    RepeatSentence(index: 0, text: "I want to fix this bug.", startTime: 0, endTime: 2.4),
    RepeatSentence(index: 1, text: "The argument does not hold up.", startTime: 2.4, endTime: 5.1),
    RepeatSentence(index: 2, text: "Let's revise the claim.", startTime: 5.1, endTime: 7.0)
]

@Test func repeatController_abRepeat_runsConfiguredRounds() throws {
    var controller = RepeatController()

    let first = try controller.startABRepeat(startTime: 10, endTime: 20, count: 3, interval: 1, speed: 1)
    #expect(first == .play(startTime: 10, endTime: 20, speed: 1))
    #expect(controller.state.currentRound == 1)

    #expect(controller.completeSegment() == .wait(duration: 1))
    #expect(controller.state.currentRound == 2)
    #expect(controller.completeInterval() == .play(startTime: 10, endTime: 20, speed: 1))

    #expect(controller.completeSegment() == .wait(duration: 1))
    #expect(controller.state.currentRound == 3)
    #expect(controller.completeInterval() == .play(startTime: 10, endTime: 20, speed: 1))

    #expect(controller.completeSegment() == .stop)
    #expect(controller.state.phase == .idle)
}

@Test func repeatController_sentenceRepeat_autoAdvancesUntilLastSentence() throws {
    var controller = RepeatController()

    let first = try controller.startSentenceRepeat(
        sentenceIndex: 0,
        sentences: repeatSentences,
        count: 2,
        interval: 0.5,
        autoAdvance: true)
    #expect(first == .play(startTime: 0, endTime: 2.4, speed: 1))

    #expect(controller.completeSegment() == .wait(duration: 0.5))
    #expect(controller.completeInterval() == .play(startTime: 0, endTime: 2.4, speed: 1))
    #expect(controller.completeSegment() == .play(startTime: 2.4, endTime: 5.1, speed: 1))
    #expect(controller.state.config?.sentenceIndex == 1)

    #expect(controller.completeSegment() == .wait(duration: 0.5))
    #expect(controller.completeInterval() == .play(startTime: 2.4, endTime: 5.1, speed: 1))
    #expect(controller.completeSegment() == .play(startTime: 5.1, endTime: 7.0, speed: 1))
    #expect(controller.state.config?.sentenceIndex == 2)

    #expect(controller.completeSegment() == .wait(duration: 0.5))
    #expect(controller.completeInterval() == .play(startTime: 5.1, endTime: 7.0, speed: 1))
    #expect(controller.completeSegment() == .stop)
}

@Test func repeatController_speedChangeAffectsCurrentAndLaterRounds() throws {
    var controller = RepeatController()

    _ = try controller.startABRepeat(startTime: 5, endTime: 10, count: 2, interval: 1, speed: 1)
    #expect(controller.setSpeed(1.5) == .updateSpeed(1.5))
    #expect(controller.state.config?.speed == 1.5)

    #expect(controller.completeSegment() == .wait(duration: 1))
    #expect(controller.completeInterval() == .play(startTime: 5, endTime: 10, speed: 1.5))
}

@Test func repeatController_pauseResumeKeepsRoundAndResumesFromPausePoint() throws {
    var controller = RepeatController()

    _ = try controller.startSentenceRepeat(
        sentenceIndex: 1,
        sentences: repeatSentences,
        count: 2,
        interval: 1)
    #expect(controller.completeSegment() == .wait(duration: 1))
    #expect(controller.completeInterval() == .play(startTime: 2.4, endTime: 5.1, speed: 1))
    #expect(controller.state.currentRound == 2)

    #expect(controller.pause(at: 3.2) == .pause)
    #expect(controller.state.phase == .paused)
    #expect(controller.state.currentRound == 2)
    #expect(controller.resume() == .play(startTime: 3.2, endTime: 5.1, speed: 1))
    #expect(controller.state.currentRound == 2)
}

@Test func repeatController_rejectsInvalidRange() throws {
    var controller = RepeatController()

    #expect(throws: RepeatControllerError.invalidRange) {
        try controller.startABRepeat(startTime: 20, endTime: 10)
    }
}
