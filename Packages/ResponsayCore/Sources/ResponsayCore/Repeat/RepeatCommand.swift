import Foundation

public enum RepeatCommand: Equatable, Sendable {
    case play(startTime: TimeInterval, endTime: TimeInterval, speed: Double)
    case wait(duration: TimeInterval)
    case pause
    case stop
    case updateSpeed(Double)
}
