import Foundation

public struct RepeatState: Equatable, Sendable {
    public var config: RepeatConfig?
    public var sentences: [RepeatSentence]
    public var currentRound: Int
    public var phase: RepeatPhase
    public var pausedAt: TimeInterval?

    public init(
        config: RepeatConfig? = nil,
        sentences: [RepeatSentence] = [],
        currentRound: Int = 0,
        phase: RepeatPhase = .idle,
        pausedAt: TimeInterval? = nil
    ) {
        self.config = config
        self.sentences = sentences
        self.currentRound = currentRound
        self.phase = phase
        self.pausedAt = pausedAt
    }

    public static let idle = RepeatState()

    public var isRepeating: Bool { phase == .playing || phase == .waiting || phase == .paused }
    public var isWaiting: Bool { phase == .waiting }
}
