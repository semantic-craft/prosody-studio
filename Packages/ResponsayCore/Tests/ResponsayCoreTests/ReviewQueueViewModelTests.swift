import Testing
import Foundation
@testable import ResponsayCore

// 305 — 到点复习 surface logic + the dual-queue bridges:
// ReviewCard queue (sentences, ReviewStore.due/grade) and the 303 e2e flow
// (followRead mistake → DrillStore.due → recordResult → out of queue).

private func tempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
}

private func coachCard(
    source: String = "i want fix bug",
    idiomatic: String = "I want to fix the bug.",
    reasons: [String] = ["缺 to"],
    dueAt: Date = Date(timeIntervalSince1970: 1_000),
    repetitions: Int = 0,
    intervalDays: Int = 0
) -> ReviewCard {
    ReviewCard(sourceText: source, language: "en-US", idiomatic: idiomatic,
               reasons: reasons, dueAt: dueAt,
               intervalDays: intervalDays, repetitions: repetitions)
}

// MARK: - isSpeakingReviewable filter

@Test func reviewable_keepsCoachCards_dropsRawDictationAndChineseTargets() {
    // Coached correction → in.
    #expect(coachCard().isSpeakingReviewable)
    // Practice feedback: idiomatic == source but reasons exist → in.
    #expect(coachCard(source: "Let me check.", idiomatic: "Let me check.").isSpeakingReviewable)
    // Raw English dictation: no correction, no reasons → out.
    #expect(!coachCard(source: "hello there", idiomatic: "hello there", reasons: []).isSpeakingReviewable)
    // Raw Chinese dictation → out.
    #expect(!coachCard(source: "今天天气不错", idiomatic: "今天天气不错", reasons: []).isSpeakingReviewable)
    // →中文 translation (no English target) → out.
    #expect(!coachCard(source: "The weather is nice.", idiomatic: "今天天气不错。", reasons: []).isSpeakingReviewable)
    // 中→英 translation (English target, differs) → in (active recall).
    #expect(coachCard(source: "今天天气不错", idiomatic: "The weather is nice today.", reasons: []).isSpeakingReviewable)
}

// MARK: - Queue VM

@Test @MainActor func load_showsOnlyDueReviewableCards() throws {
    let store = try SQLiteReviewStore(databaseURL: tempDB())
    let now = Date()
    try store.save(coachCard(source: "a", dueAt: now.addingTimeInterval(-60)))            // due
    try store.save(coachCard(source: "今天天气", idiomatic: "今天天气", reasons: [],
                             dueAt: now.addingTimeInterval(-60)))                          // due, not reviewable
    try store.save(coachCard(source: "b", dueAt: now.addingTimeInterval(86_400)))          // not due yet

    let vm = ReviewQueueViewModel(store: store, now: { now })
    vm.load()
    #expect(vm.queue.count == 1)
    #expect(vm.current?.sourceText == "a")
    #expect(vm.remaining == 1)
}

@Test @MainActor func emptyStore_hasHonestEmptyState() throws {
    let vm = ReviewQueueViewModel(store: try SQLiteReviewStore(databaseURL: tempDB()))
    vm.load()
    #expect(vm.current == nil)
    #expect(vm.isFinished == false)   // nothing was due — not "all done", just empty
    #expect(vm.remaining == 0)
}

@Test @MainActor func gradePass_advancesAndReschedulesOutOfDue() throws {
    let store = try SQLiteReviewStore(databaseURL: tempDB())
    let now = Date()
    try store.save(coachCard(dueAt: now.addingTimeInterval(-60)))

    let vm = ReviewQueueViewModel(store: store, now: { now })
    vm.load()
    #expect(vm.current != nil)
    vm.reveal()
    #expect(vm.isRevealed)
    vm.grade(.good)

    // Session: card consumed, not re-queued.
    #expect(vm.current == nil)
    #expect(vm.isFinished)
    #expect(vm.reviewedCount == 1)
    // Store: no longer due now (SM-2 moved it ≥1 day out).
    #expect(try store.due(now: now, limit: 10).isEmpty)
}

@Test @MainActor func gradeFail_requeuesInSession_andStaysNearInStore() throws {
    let store = try SQLiteReviewStore(databaseURL: tempDB())
    let now = Date()
    // Second-rep card: pass → 6d interval, fail → reset to 1d. The gap between
    // the two is the rubric's 答对→出队 / 答错→留队, in honest SM-2 terms.
    try store.save(coachCard(dueAt: now.addingTimeInterval(-60), repetitions: 1, intervalDays: 1))

    let vm = ReviewQueueViewModel(store: store, now: { now })
    vm.load()
    vm.reveal()
    vm.grade(.wrong)

    // Session: failed card comes back at the end of today's queue (留队).
    #expect(vm.current != nil)
    #expect(vm.isRevealed == false)
    // Store: due again within 2 days (interval reset to 1d)…
    let twoDays = now.addingTimeInterval(2 * 86_400)
    #expect(try store.due(now: twoDays, limit: 10).count == 1)

    // …whereas the SAME starting card graded .good would be ~6 days out.
    let store2 = try SQLiteReviewStore(databaseURL: tempDB())
    try store2.save(coachCard(dueAt: now.addingTimeInterval(-60), repetitions: 1, intervalDays: 1))
    let vm2 = ReviewQueueViewModel(store: store2, now: { now })
    vm2.load()
    vm2.grade(.good)
    #expect(try store2.due(now: twoDays, limit: 10).isEmpty)   // 答对 → 出队
}

// Verifier flag A — dictation sediment (oldest-due, never reviewable) must not
// eclipse reviewable cards sitting beyond the first due page.
@Test @MainActor func load_seesPastDictationSediment() throws {
    let store = try SQLiteReviewStore(databaseURL: tempDB())
    let now = Date()
    // 120 sediment rows, all due and older than the coach card.
    for i in 0..<120 {
        try store.save(coachCard(
            source: "听写第\(i)句", idiomatic: "听写第\(i)句", reasons: [],
            dueAt: now.addingTimeInterval(TimeInterval(-10_000 + i))))
    }
    try store.save(coachCard(dueAt: now.addingTimeInterval(-60)))   // the one real card

    let vm = ReviewQueueViewModel(store: store, now: { now })
    vm.load()
    #expect(vm.queue.count == 1)
    #expect(vm.current?.idiomatic == "I want to fix the bug.")
}

// Verifier flag B — re-extraction must hit the SAME row (content identity), so
// upsert's content-only conflict branch preserves SM-2 instead of re-minting
// an immediately-due duplicate on every screen visit.
@Test func reExtraction_isStable_andKeepsSM2Progress() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let item = CaptureItem(sourceText: "i want fix bug", language: "en-US",
                           idiomatic: "I want to fix the bug.", reasons: ["缺 to"])
    let first = try #require(EnglishMistakeExtractor().extract(from: item).first)
    let second = try #require(EnglishMistakeExtractor().extract(from: item).first)
    #expect(first.id == second.id)   // deterministic content identity

    try store.upsert(first)
    try store.recordResult(mistakeID: first.id, correct: true, reviewedAt: Date())
    #expect(try store.due(now: Date(), limit: 50).isEmpty)

    // Screen revisit: re-extract + re-upsert → still one row, still not due.
    try store.upsert(second)
    #expect(try store.all().count == 1)
    #expect(try store.due(now: Date(), limit: 50).isEmpty)
}

@Test func followRead_identityIsContentStable() throws {
    let feedback = SpeechFeedback(
        targetText: "I want to fix the bug", recognizedText: "I want fix the bug",
        similarity: 0.8, message: "再试一次")
    let a = try #require(MistakeRecord.followRead(from: feedback))
    let b = try #require(MistakeRecord.followRead(from: feedback))
    #expect(a.id == b.id)
}

// MARK: - 303 → 305 e2e: 存入复习 lands in the due-driven drill seed

@Test func followReadMistake_isDueImmediately_thenLeavesQueueWhenCorrect() throws {
    let store = try SQLiteDrillStore(databaseURL: tempDB())
    let feedback = SpeechFeedback(
        targetText: "I want to fix the bug", recognizedText: "I want fix the bug",
        similarity: 0.8, message: "再试一次")
    let mistake = try #require(MistakeRecord.followRead(from: feedback))
    try store.upsert(mistake)

    // 存入复习 → immediately due (initial due = created).
    let due = try store.due(now: Date(), limit: 50)
    #expect(due.contains { $0.id == mistake.id })

    // Drilled correctly → SM-2 moves it out of today's queue.
    try store.recordResult(mistakeID: mistake.id, correct: true, reviewedAt: Date())
    #expect(try !store.due(now: Date(), limit: 50).contains { $0.id == mistake.id })

    // Drilled wrong (fresh store) → still due tomorrow+ (interval 1d), back in 2 days.
    let store2 = try SQLiteDrillStore(databaseURL: tempDB())
    try store2.upsert(mistake)
    try store2.recordResult(mistakeID: mistake.id, correct: false, reviewedAt: Date())
    #expect(try store2.due(now: Date().addingTimeInterval(2 * 86_400), limit: 50)
        .contains { $0.id == mistake.id })
}
