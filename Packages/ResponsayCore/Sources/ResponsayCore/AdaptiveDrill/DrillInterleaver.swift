import Foundation

/// Reorders mistakes so consecutive drills mix categories (interleaving: avoid
/// blocked practice of one category). Round-robins across category groups in
/// their first-appearance order, spreading same-category items maximally apart.
public struct DrillInterleaver: Sendable {
    public init() {}

    public func order(_ mistakes: [MistakeRecord]) -> [MistakeRecord] {
        var groups: [[MistakeRecord]] = []
        var indexByCategory: [String: Int] = [:]
        for mistake in mistakes {
            if let i = indexByCategory[mistake.category] {
                groups[i].append(mistake)
            } else {
                indexByCategory[mistake.category] = groups.count
                groups.append([mistake])
            }
        }

        var ordered: [MistakeRecord] = []
        var cursor = 0
        while ordered.count < mistakes.count {
            let group = groups[cursor % groups.count]
            let round = cursor / groups.count
            if round < group.count { ordered.append(group[round]) }
            cursor += 1
        }
        return ordered
    }
}
