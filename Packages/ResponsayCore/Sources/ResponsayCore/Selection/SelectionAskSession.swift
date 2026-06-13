import Foundation

/// General vs legal ask. Legal mode keeps `[待核]` discipline on answers.
public enum SelectionAskMode: String, Sendable, Codable, Equatable {
    case general
    case legal
}

/// One bounded turn: a transcribed voice question + its (eventual) answer.
public struct AskTurn: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let question: String
    public var answer: String?

    public init(id: UUID = UUID(), question: String, answer: String? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

/// Selection → voice question → multi-turn follow-up, as a **bounded structured**
/// ask (issue 155 / ADR-0022) — NOT a free-form chat box. The selection is
/// privacy-truncated (169); turns are capped; legal mode preserves `[待核]`.
public struct SelectionAskSession: Sendable, Equatable {
    /// Hard cap on follow-ups — bounded, not an open chat.
    public static let maxTurns = 8

    public let selection: String
    public let wasTruncated: Bool
    public let originalLength: Int
    public let mode: SelectionAskMode
    public var pinned: Bool
    public private(set) var turns: [AskTurn]

    public var reachedTurnLimit: Bool { turns.count >= Self.maxTurns }

    public init(
        rawSelection: String,
        mode: SelectionAskMode = .general,
        limit: Int = SelectionAskPolicy.defaultLimit,
        pinned: Bool = false
    ) {
        let truncation = SelectionAskPolicy.truncate(rawSelection, limit: limit)
        self.selection = truncation.text
        self.wasTruncated = truncation.wasTruncated
        self.originalLength = truncation.originalLength
        self.mode = mode
        self.pinned = pinned
        self.turns = []
    }

    /// Append a transcribed voice question. Beyond `maxTurns` it is dropped
    /// (bounded ask) — check `reachedTurnLimit` to surface that in the UI.
    public func asking(_ question: String) -> SelectionAskSession {
        guard !reachedTurnLimit else { return self }
        var copy = self
        copy.turns.append(AskTurn(question: question))
        return copy
    }

    /// Fill in the answer for the most recent turn.
    public func answeringLast(_ answer: String) -> SelectionAskSession {
        guard let last = turns.indices.last else { return self }
        var copy = self
        copy.turns[last].answer = answer
        return copy
    }

    public func settingPinned(_ value: Bool) -> SelectionAskSession {
        var copy = self
        copy.pinned = value
        return copy
    }

    /// Legal mode: reconcile an answer's fact coordinates through the
    /// `NewCoordinateGuard`, so any new law/case/date stays `[待核]` (pending).
    /// Returns the anchors the UI should render next to the answer.
    public func guardedLegalAnchors(for answer: String, existing: [VerificationAnchor] = []) -> [VerificationAnchor] {
        guard mode == .legal else { return [] }
        return NewCoordinateGuard().reconcile(text: answer, existing: existing)
    }
}
