import Foundation

/// 146 — phases for the listen → shadow → feedback loop.
public enum FollowReadPhase: Equatable, Sendable {
    case idle
    case playingReference
    case recording
    case processing
    case feedback
    case failed(String)
}