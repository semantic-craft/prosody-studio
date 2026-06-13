import Foundation
import Observation
import ResponsayCore

@MainActor
@Observable
final class HomeViewModel {
    var recentCount = 0
    var dueCount = 0
    var latestCard: ReviewCard?
    var errorMessage: String?

    @ObservationIgnored private var store: (any ReviewStore)?

    init(store: (any ReviewStore)? = nil) {
        self.store = store
    }

    func load() {
        do {
            let store = try activeStore()
            let recent = try store.recent(10)
            recentCount = try store.count()
            dueCount = try store.due(now: Date(), limit: 100).count
            latestCard = recent.first
            errorMessage = nil
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
