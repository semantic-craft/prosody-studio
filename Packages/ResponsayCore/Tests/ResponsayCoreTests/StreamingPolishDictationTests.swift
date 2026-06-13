import Testing
import Foundation
@testable import ResponsayCore

/// 232 — 改写原话听写 routes to the streaming hook (边生成边落字) and falls back to the batch
/// polish+insert when the hook can't deliver. The streaming closure inserts externally, so the VM's
/// own inserter staying empty proves the stream handled it (and being used proves the fallback ran).
@Test @MainActor func polishedDictation_streamsViaHookAndSkipsBatchInsert() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "嗯这个方案大概可以"
    let inserter = MockTextInserter()
    var streamedInput: String?
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter,
        polisher: MockTextPolishAPI(),
        streamingInsert: { text, mode, targetLanguage in
            streamedInput = text
            return .streamed(text: "这个方案大概可以。")
        })

    await vm.toggle(outputMode: .polishedTranscript)   // start listening
    await vm.toggle(outputMode: .polishedTranscript)   // stop + process

    #expect(streamedInput == "嗯这个方案大概可以")   // the streaming hook received the transcript
    #expect(inserter.inserted.isEmpty)               // VM did NOT batch-insert — streaming handled it
}

@Test @MainActor func polishedDictation_unsupportedStreamingFallsBackToBatch() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "raw text"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter,
        polisher: MockTextPolishAPI(),
        streamingInsert: { _, _, _ in .unsupportedFallback(reason: "streaming disabled") })

    await vm.toggle(outputMode: .polishedTranscript)
    await vm.toggle(outputMode: .polishedTranscript)

    #expect(inserter.inserted == ["raw text"])
    #expect(vm.phase == .idle)
    #expect(vm.errorMessage == nil)
}

@Test @MainActor func polishedDictation_failedStreamingRecordsActualInsertedTextWithoutBatchDuplicate() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "source text"
    let inserter = MockTextInserter()
    let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = FileCaptureStore(fileURL: storeURL)
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        polisher: MockTextPolishAPI(),
        streamingInsert: { _, _, _ in .failed(reason: "stream broke", insertedText: "partial text") })

    await vm.toggle(outputMode: .polishedTranscript)
    await vm.toggle(outputMode: .polishedTranscript)

    #expect(inserter.inserted.isEmpty)
    #expect(vm.phase == .error)
    #expect(vm.errorMessage == "stream broke")
    #expect(vm.captureResult?.insertText == "partial text")
    let recent = try store.recent(1)
    #expect(recent.first?.idiomatic == "partial text")
}

@Test @MainActor func polishedDictation_fallsBackToBatchWhenStreamUnsupported() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "raw text"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter,
        polisher: MockTextPolishAPI(),
        streamingInsert: { _, _, _ in .unsupportedFallback(reason: "streaming unavailable") })

    await vm.toggle(outputMode: .polishedTranscript)
    await vm.toggle(outputMode: .polishedTranscript)

    #expect(inserter.inserted == ["raw text"])   // batch polish+insert ran (mock polish echoes input)
}

@Test @MainActor func polishedDictation_withoutHookStillBatchInserts() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "hello"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter,
        polisher: MockTextPolishAPI())   // no streamingInsert → original behavior

    await vm.toggle(outputMode: .polishedTranscript)
    await vm.toggle(outputMode: .polishedTranscript)

    #expect(inserter.inserted == ["hello"])
}
