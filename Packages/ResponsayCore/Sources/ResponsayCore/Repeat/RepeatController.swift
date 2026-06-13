import Foundation

public struct RepeatController: Sendable {
    public private(set) var state: RepeatState

    public init(state: RepeatState = .idle) {
        self.state = state
    }

    public mutating func startABRepeat(
        startTime: TimeInterval,
        endTime: TimeInterval,
        count: Int = 3,
        interval: TimeInterval = 1.5,
        speed: Double = 1.0
    ) throws -> RepeatCommand {
        try validateRange(startTime: startTime, endTime: endTime)
        let config = RepeatConfig(
            mode: .ab,
            startTime: startTime,
            endTime: endTime,
            count: count,
            interval: interval,
            speed: speed)
        state = RepeatState(config: config, currentRound: 1, phase: .playing)
        return playCommand(for: config)
    }

    public mutating func startSentenceRepeat(
        sentenceIndex: Int,
        sentences: [RepeatSentence],
        count: Int = 3,
        interval: TimeInterval = 1.5,
        speed: Double = 1.0,
        autoAdvance: Bool = false
    ) throws -> RepeatCommand {
        guard !sentences.isEmpty else { throw RepeatControllerError.emptySentences }
        guard let sentence = sentences.first(where: { $0.index == sentenceIndex }) else {
            throw RepeatControllerError.sentenceNotFound(sentenceIndex)
        }
        try validateRange(startTime: sentence.startTime, endTime: sentence.endTime)
        let config = configForSentence(
            sentence,
            count: count,
            interval: interval,
            speed: speed,
            autoAdvance: autoAdvance)
        state = RepeatState(config: config, sentences: sentences, currentRound: 1, phase: .playing)
        return playCommand(for: config)
    }

    public mutating func startFullRepeat(
        sentences: [RepeatSentence],
        count: Int = 1,
        interval: TimeInterval = 0,
        speed: Double = 1.0
    ) throws -> RepeatCommand {
        guard let first = sentences.first, let last = sentences.last else {
            throw RepeatControllerError.emptySentences
        }
        try validateRange(startTime: first.startTime, endTime: last.endTime)
        let config = RepeatConfig(
            mode: .full,
            startTime: first.startTime,
            endTime: last.endTime,
            count: count,
            interval: interval,
            speed: speed)
        state = RepeatState(config: config, sentences: sentences, currentRound: 1, phase: .playing)
        return playCommand(for: config)
    }

    public mutating func completeSegment() -> RepeatCommand {
        guard var config = state.config else { return .stop }
        guard state.phase == .playing else { return commandForCurrentPhase() }

        if state.currentRound < config.count {
            state.currentRound += 1
            state.phase = .waiting
            return .wait(duration: config.interval)
        }

        if config.mode == .sentence,
           config.autoAdvance,
           let next = nextSentence(after: config.sentenceIndex) {
            config = configForSentence(
                next,
                count: config.count,
                interval: config.interval,
                speed: config.speed,
                autoAdvance: true)
            state.config = config
            state.currentRound = 1
            state.phase = .playing
            return playCommand(for: config)
        }

        stop()
        return .stop
    }

    public mutating func completeInterval() -> RepeatCommand {
        guard let config = state.config, state.phase == .waiting else {
            return commandForCurrentPhase()
        }
        state.phase = .playing
        return playCommand(for: config)
    }

    public mutating func pause(at currentTime: TimeInterval) -> RepeatCommand {
        guard state.phase == .playing, let config = state.config else { return commandForCurrentPhase() }
        state.pausedAt = min(max(currentTime, config.startTime), config.endTime)
        state.phase = .paused
        return .pause
    }

    public mutating func resume() -> RepeatCommand {
        guard var config = state.config, state.phase == .paused else {
            return commandForCurrentPhase()
        }
        config.startTime = state.pausedAt ?? config.startTime
        state.config = config
        state.pausedAt = nil
        state.phase = .playing
        return playCommand(for: config)
    }

    public mutating func setSpeed(_ speed: Double) -> RepeatCommand {
        guard var config = state.config else { return .updateSpeed(max(0.5, min(speed, 2.0))) }
        config.speed = max(0.5, min(speed, 2.0))
        state.config = config
        return .updateSpeed(config.speed)
    }

    public mutating func stop() {
        state = .idle
    }

    private func commandForCurrentPhase() -> RepeatCommand {
        switch state.phase {
        case .idle: .stop
        case .playing:
            state.config.map(playCommand) ?? .stop
        case .waiting:
            .wait(duration: state.config?.interval ?? 0)
        case .paused:
            .pause
        }
    }

    private func playCommand(for config: RepeatConfig) -> RepeatCommand {
        .play(startTime: config.startTime, endTime: config.endTime, speed: config.speed)
    }

    private func configForSentence(
        _ sentence: RepeatSentence,
        count: Int,
        interval: TimeInterval,
        speed: Double,
        autoAdvance: Bool
    ) -> RepeatConfig {
        RepeatConfig(
            mode: .sentence,
            startTime: sentence.startTime,
            endTime: sentence.endTime,
            count: count,
            interval: interval,
            speed: speed,
            sentenceIndex: sentence.index,
            autoAdvance: autoAdvance)
    }

    private func nextSentence(after index: Int) -> RepeatSentence? {
        state.sentences
            .sorted { $0.index < $1.index }
            .first { $0.index > index }
    }

    private func validateRange(startTime: TimeInterval, endTime: TimeInterval) throws {
        guard startTime >= 0, endTime > startTime else {
            throw RepeatControllerError.invalidRange
        }
    }
}
