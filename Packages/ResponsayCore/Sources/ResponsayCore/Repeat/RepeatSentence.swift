import Foundation

public struct RepeatSentence: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { index }

    public let index: Int
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(index: Int, text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
