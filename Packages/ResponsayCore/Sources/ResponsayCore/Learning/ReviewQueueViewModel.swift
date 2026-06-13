import Foundation
import Observation

/// 到点复习 session driver (issue 305) — the first runtime consumer of the
/// `ReviewStore` SRS API (`due`/`grade`) on macOS.
///
/// Queue adjudication (305): the app keeps TWO spaced-repetition queues on
/// purpose — `ReviewCard`/`ReviewStore` holds whole coached sentences (every
/// capture lands here via `ReviewCaptureStore`) and is reviewed by re-speaking;
/// `MistakeRecord`/`DrillStore` holds structured mistakes drilled by the 071
/// generator. Shapes and exercises differ, so neither retires; this VM surfaces
/// the sentence queue, while the drill session seeds from `DrillStore.due()`.
///
/// Pure session logic lives here so it is unit-testable; the view only renders.
@MainActor
@Observable
public final class ReviewQueueViewModel {
    public private(set) var queue: [ReviewCard] = []
    public private(set) var index = 0
    /// Recall-first UX: the target sentence stays hidden until the user tried.
    public private(set) var isRevealed = false
    public private(set) var reviewedCount = 0

    private let store: any ReviewStore
    private let now: () -> Date

    public init(store: any ReviewStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public var current: ReviewCard? { index < queue.count ? queue[index] : nil }
    public var remaining: Int { max(0, queue.count - index) }
    public var isFinished: Bool { !queue.isEmpty && current == nil }

    /// Load today's due cards, keeping only sentence-reviewable ones (the
    /// review_cards table also holds raw dictation/translation rows — see
    /// `ReviewCard.isSpeakingReviewable`).
    ///
    /// Paged scan (305 verifier flag A): sediment rows (raw dictation, never
    /// gradable, due_at oldest-first) would otherwise occupy the whole due
    /// window and permanently eclipse the reviewable cards behind them — the
    /// scan widens geometrically until enough reviewable cards are found or
    /// the due set is exhausted.
    public func load(limit: Int = 20) {
        var reviewable: [ReviewCard] = []
        var scanLimit = max(limit * 5, 100)
        while true {
            let due = (try? store.due(now: now(), limit: scanLimit)) ?? []
            reviewable = due.filter(\.isSpeakingReviewable)
            if reviewable.count >= limit || due.count < scanLimit || scanLimit >= 100_000 { break }
            scanLimit *= 4
        }
        queue = Array(reviewable.prefix(limit))
        index = 0
        isRevealed = false
        reviewedCount = 0
    }

    public func reveal() { isRevealed = true }

    /// Grade the current card: SM-2 reschedules it in the store (grade < 3 →
    /// tomorrow; passes grow the interval). A failed card is also re-queued at
    /// the END of this session (留队), so "wrong" gets a second try today even
    /// though its stored dueAt already moved to tomorrow.
    public func grade(_ grade: ReviewGrade) {
        guard let card = current else { return }
        let rescheduled = (try? store.grade(card, grade: grade, reviewedAt: now())) ?? card
        if grade.rawValue < ReviewGrade.hesitant.rawValue {
            queue.append(rescheduled)
        }
        reviewedCount += 1
        index += 1
        isRevealed = false
    }
}

public extension ReviewCard {
    /// True when the card is worth re-speaking on the review surface (305):
    /// it must carry an English target sentence, and either a coaching signal
    /// (reasons) or an actual correction (idiomatic ≠ source). Raw Chinese
    /// dictation and →中文 translation rows stay out of the queue.
    var isSpeakingReviewable: Bool {
        let target = idiomatic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        guard target.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return false }
        return !reasons.isEmpty || target != sourceText
    }
}
