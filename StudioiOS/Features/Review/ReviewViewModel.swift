import Foundation
import Observation
import ResponsayCore

@MainActor
@Observable
final class ReviewViewModel {
    var dueCards: [ReviewCard] = []
    var recentCards: [ReviewCard] = []
    var totalCount = 0
    var errorMessage: String?

    @ObservationIgnored private var store: (any ReviewStore)?

    init(store: (any ReviewStore)? = nil) {
        self.store = store
    }

    func load() {
        do {
            let store = try activeStore()
            dueCards = try store.due(now: Date(), limit: 20)
            recentCards = try store.recent(8)
            totalCount = try store.count()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func grade(_ card: ReviewCard, as grade: ReviewGrade) {
        do {
            let store = try activeStore()
            _ = try store.grade(card, grade: grade)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activeStore() throws -> any ReviewStore {
        if let store { return store }
        let newStore = try SQLiteReviewStore.defaultStore()
        store = newStore
        return newStore
    }
}
