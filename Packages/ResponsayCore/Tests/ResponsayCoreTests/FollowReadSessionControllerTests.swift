import Foundation
import Testing
@testable import ResponsayCore

@Test @MainActor func followReadSession_referenceToRecordingToFeedback() {
    let session = FollowReadSessionController()
    let analysis = ProsodyAnalysis.holdsUp

    session.beginReferencePlayback(for: analysis)
    #expect(session.phase == .playingReference)
    #expect(session.targetText == analysis.text)

    session.referencePlaybackFinished()
    #expect(session.phase == .recording)

    session.beginProcessing()
    #expect(session.phase == .processing)

    let feedback = SpeechFeedback(
        targetText: analysis.text,
        recognizedText: analysis.text,
        similarity: 1,
        message: "ok")
    session.complete(with: feedback)
    #expect(session.phase == .feedback)
    #expect(session.feedback?.similarity == 1)
}

@Test @MainActor func followReadSession_retryReturnsToIdle() {
    let session = FollowReadSessionController()
    session.beginReferencePlayback(for: .sample)
    session.referencePlaybackFinished()
    session.complete(with: SpeechFeedback(
        targetText: "x", recognizedText: "y", similarity: 0.5, message: "m"))
    session.retry()
    #expect(session.phase == .idle)
    #expect(session.feedback == nil)
}

@Test @MainActor func followReadSession_failPreservesMessage() {
    let session = FollowReadSessionController()
    session.beginReferencePlayback(for: .sample)
    session.fail("mic denied")
    #expect(session.phase == .failed("mic denied"))
}

// 猎虫③ F2 — 取消/换句后迟到的云端转写不得让已死会话还魂：
// complete 只在 .processing 生效，.idle 下是 no-op。
@Test @MainActor func followReadSession_lateCompleteAfterCancelIsIgnored() {
    let session = FollowReadSessionController()
    session.beginReferencePlayback(for: ProsodyAnalysis.holdsUp)
    session.referencePlaybackFinished()
    session.beginProcessing()
    session.cancel()                       // 用户点了停止 / 切句
    #expect(session.phase == .idle)

    session.complete(with: SpeechFeedback(
        targetText: "x", recognizedText: "x", similarity: 1, message: "x"))

    #expect(session.phase == .idle)        // 不还魂
    #expect(session.feedback == nil)
}

@Test @MainActor func followReadSession_lateFailAfterCancelIsIgnored() {
    let session = FollowReadSessionController()
    session.beginProcessing()
    session.cancel()
    session.fail("network")
    #expect(session.phase == .idle)
}
