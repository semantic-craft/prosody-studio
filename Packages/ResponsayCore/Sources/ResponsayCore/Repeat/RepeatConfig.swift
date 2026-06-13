import Foundation

public struct RepeatConfig: Codable, Equatable, Sendable {
    public let mode: RepeatMode
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var count: Int
    public var interval: TimeInterval
    public var speed: Double
    public var sentenceIndex: Int
    public var autoAdvance: Bool

    public init(
        mode: RepeatMode,
        startTime: TimeInterval,
        endTime: TimeInterval,
        count: Int,
        interval: TimeInterval,
        speed: Double,
        sentenceIndex: Int = 0,
        autoAdvance: Bool = false
    ) {
        self.mode = mode
        self.startTime = startTime
        self.endTime = endTime
        self.count = max(1, count)
        self.interval = max(0, interval)
        self.speed = max(0.5, min(speed, 2.0))
        self.sentenceIndex = sentenceIndex
        self.autoAdvance = autoAdvance
    }
}
