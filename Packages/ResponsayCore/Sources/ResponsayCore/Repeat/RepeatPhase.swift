import Foundation

public enum RepeatPhase: String, Codable, Sendable {
    case idle
    case playing
    case waiting
    case paused
}
