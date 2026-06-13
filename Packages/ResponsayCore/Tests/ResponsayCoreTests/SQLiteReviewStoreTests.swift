import Foundation
import Testing
@testable import ResponsayCore

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func sqliteReviewStore_migratesEmptyV1Store() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))

    #expect(try store.schemaVersion() == AppSchemaVersion.current)
    #expect(try store.count() == 0)
    #expect(try store.recent(10).isEmpty)
}

@Test func sqliteReviewStore_importsCapturesWithoutDeletingSource() throws {
    let directory = try tempDirectory()
    let capturesURL = directory.appendingPathComponent("captures.json")
    let old = CaptureItem(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        createdAt: Date(timeIntervalSince1970: 10),
        sourceText: "我想修复这个 bug",
        language: "zh-CN",
        idiomatic: "I want to fix this bug.",
        reasons: ["English needs the infinitive after want."])
    let newer = CaptureItem(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        createdAt: Date(timeIntervalSince1970: 20),
        sourceText: "i want fix bug",
        language: "en-US",
        idiomatic: "I want to fix the bug.",
        reasons: ["Add to before fix."])
    try JSONEncoder().encode([old, newer]).write(to: capturesURL)

    let store = try SQLiteReviewStore(
        databaseURL: directory.appendingPathComponent("review.sqlite"),
        importCapturesFrom: capturesURL)
    let recent = try store.recent(10)

    #expect(try store.count() == 2)
    #expect(recent.map(\.id) == [newer.id, old.id])
    #expect(recent.first?.dueAt == newer.createdAt)
    #expect(recent.first?.reasons == newer.reasons)
    #expect(FileManager.default.fileExists(atPath: capturesURL.path))
}

@Test func sqliteReviewStore_dueReturnsStableCards() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let due = ReviewCard(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        createdAt: Date(timeIntervalSince1970: 1),
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 5))
    let future = ReviewCard(
        createdAt: Date(timeIntervalSince1970: 2),
        sourceText: "b",
        language: "en-US",
        idiomatic: "B.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 50))

    try store.save(future)
    try store.save(due)
    let cards = try store.due(now: Date(timeIntervalSince1970: 10), limit: 10)

    #expect(cards.map(\.id) == [due.id])
}

@Test func sm2Scheduler_easyReviewAdvancesDueDateAndRepetitions() throws {
    let reviewedAt = Date(timeIntervalSince1970: 100)
    let card = ReviewCard(
        sourceText: "i want fix bug",
        language: "en-US",
        idiomatic: "I want to fix the bug.",
        reasons: [])

    let next = SM2Scheduler.schedule(card, grade: .easy, reviewedAt: reviewedAt)

    #expect(next.repetitions == 1)
    #expect(next.intervalDays == 1)
    #expect(next.dueAt == reviewedAt.addingTimeInterval(86_400))
    #expect(next.easeFactor > card.easeFactor)
}

@Test func sm2Scheduler_failedReviewResetsRepetitions() throws {
    let reviewedAt = Date(timeIntervalSince1970: 200)
    let card = ReviewCard(
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        intervalDays: 12,
        repetitions: 4,
        easeFactor: 2.4)

    let next = SM2Scheduler.schedule(card, grade: .wrong, reviewedAt: reviewedAt)

    #expect(next.repetitions == 0)
    #expect(next.intervalDays == 1)
    #expect(next.easeFactor < card.easeFactor)
    #expect(next.masteryStars >= 1)
}

@Test func sqliteReviewStore_gradePersistsSM2State() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let card = ReviewCard(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        createdAt: Date(timeIntervalSince1970: 1),
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 1))
    try store.save(card)

    let updated = try store.grade(card, grade: .good, reviewedAt: Date(timeIntervalSince1970: 10))
    let fetched = try #require(try store.recent(1).first)

    #expect(fetched.id == card.id)
    #expect(fetched.repetitions == updated.repetitions)
    #expect(fetched.intervalDays == 1)
    #expect(fetched.dueAt == Date(timeIntervalSince1970: 10 + 86_400))
}

@Test func reviewCaptureStoreWritesCaptureItemsIntoReviewStore() throws {
    let directory = try tempDirectory()
    let reviewStore = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let captureStore = ReviewCaptureStore(reviewStore: reviewStore)
    let capture = CaptureItem(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: "我想修复这个 bug",
        language: "zh-CN",
        idiomatic: "I want to fix this bug.",
        reasons: ["Natural infinitive."])

    try captureStore.save(capture)

    #expect(try reviewStore.count() == 1)
    #expect(try captureStore.recent(1).first == capture)
}
