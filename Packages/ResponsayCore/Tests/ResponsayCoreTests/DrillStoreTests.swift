import Foundation
import Testing
@testable import ResponsayCore

// 071 slice 4 — local persistence: mistakes + per-mistake SM-2 spacing +
// attempt/success counts (frequency) + mastery. Reuses SM2Scheduler (issue 040).

private func tempDB() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("drills.sqlite")
}

private func mistake(_ id: String, at seconds: TimeInterval = 0) -> MistakeRecord {
    MistakeRecord(
        id: UUID(uuidString: id)!, category: "语气",
        prompt: "你必须明天做完", expected: "Could you finish this by tomorrow?",
        explanation: "更礼貌", drillPrompts: ["Could you …?"],
        createdAt: Date(timeIntervalSince1970: seconds), sourceLanguage: "zh-CN")
}

@Test func drillStore_upsertAndAllRoundTrip() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let m = mistake("11111111-1111-1111-1111-111111111111", at: 5)
    try store.upsert(m)

    let all = try store.all()
    #expect(all.count == 1)
    #expect(all.first == m)   // full content fidelity incl drillPrompts
}

@Test func drillStore_upsertPreservesProgress() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let id = "22222222-2222-2222-2222-222222222222"
    try store.upsert(mistake(id))
    try store.recordResult(mistakeID: UUID(uuidString: id)!, correct: true,
                           reviewedAt: Date(timeIntervalSince1970: 1000))

    // Re-upsert (e.g. the same mistake seen again) must NOT wipe SM-2 progress.
    let original = mistake(id)
    let changed = MistakeRecord(id: original.id, category: "语气",
                                prompt: original.prompt, expected: original.expected,
                                explanation: "改了说明", drillPrompts: original.drillPrompts)
    try store.upsert(changed)

    let progress = try #require(try store.progress(for: changed.id))
    #expect(progress.attempts == 1)
    #expect(try store.all().first?.explanation == "改了说明")   // content did update
}

@Test func drillStore_recordCorrectAdvancesSM2() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let m = mistake("33333333-3333-3333-3333-333333333333")
    try store.upsert(m)
    try store.recordResult(mistakeID: m.id, correct: true, reviewedAt: Date(timeIntervalSince1970: 1000))

    let p = try #require(try store.progress(for: m.id))
    #expect(p.attempts == 1)
    #expect(p.successes == 1)
    #expect(p.repetitions == 1)
    #expect(p.intervalDays == 1)
    #expect(p.dueAt == Date(timeIntervalSince1970: 1000 + 86_400))
}

@Test func drillStore_recordWrongResetsRepetitions() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let m = mistake("44444444-4444-4444-4444-444444444444")
    try store.upsert(m)
    try store.recordResult(mistakeID: m.id, correct: true, reviewedAt: Date(timeIntervalSince1970: 1))
    try store.recordResult(mistakeID: m.id, correct: true, reviewedAt: Date(timeIntervalSince1970: 2))
    try store.recordResult(mistakeID: m.id, correct: false, reviewedAt: Date(timeIntervalSince1970: 3))

    let p = try #require(try store.progress(for: m.id))
    #expect(p.attempts == 3)
    #expect(p.successes == 2)
    #expect(p.repetitions == 0)
    #expect(p.intervalDays == 1)
}

@Test func drillStore_dueReturnsOnlyDueMistakes() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let due = mistake("55555555-5555-5555-5555-555555555555", at: 10)
    let pushed = mistake("66666666-6666-6666-6666-666666666666", at: 20)
    try store.upsert(due)
    try store.upsert(pushed)
    try store.recordResult(mistakeID: pushed.id, correct: true, reviewedAt: Date(timeIntervalSince1970: 20))

    let result = try store.due(now: Date(timeIntervalSince1970: 100), limit: 10)
    #expect(result.map(\.id) == [due.id])
}

@Test func drillStore_masteryAndSuccessRate() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let m = mistake("77777777-7777-7777-7777-777777777777")
    try store.upsert(m)
    let fresh = try #require(try store.progress(for: m.id))
    #expect(fresh.masteryStars == 1)            // untrained
    #expect(fresh.successRate == 0)
}

@Test func drillStore_deleteAndReopen() throws {
    let url = try tempDB()
    let first = try SQLiteDrillStore(databaseURL: url)
    try first.upsert(mistake("88888888-8888-8888-8888-888888888888"))
    let reopened = try SQLiteDrillStore(databaseURL: url)
    #expect(try reopened.all().count == 1)
    try reopened.delete(id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!)
    #expect(try reopened.all().isEmpty)
}
