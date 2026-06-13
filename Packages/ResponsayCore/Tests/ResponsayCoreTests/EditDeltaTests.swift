import Testing
import Foundation
@testable import ResponsayCore

/// Diff between what we inserted and what the user left after editing — the data
/// shape borrowed from the Typeless RE report §5.2 (`isLargeModify` / added /
/// removed) plus the word-region substitutions the hotword flywheel learns from.
@Suite struct EditDeltaTests {
    @Test func noEditYieldsEmptyDelta() {
        let delta = EditDelta.compute(inserted: "今天天气不错", userFinal: "今天天气不错")
        #expect(delta.addedCount == 0)
        #expect(delta.removedCount == 0)
        #expect(delta.isLargeModify == false)
        #expect(delta.substitutions.isEmpty)
    }

    @Test func chineseTermFixIsSmallWithOneSubstitution() {
        // 个人信息处理着 -> 个人信息处理者 ; the run is bounded by the comma.
        let delta = EditDelta.compute(
            inserted: "个人信息处理着，应遵循正当性原则",
            userFinal: "个人信息处理者，应遵循正当性原则")
        #expect(delta.isLargeModify == false)
        #expect(delta.substitutions == [WordSubstitution(from: "个人信息处理着", to: "个人信息处理者")])
    }

    @Test func mixedTermMergeYieldsRegionSubstitution() {
        // "Quinn three" (2 tokens) -> "Qwen3" (1 token): a changed region, both sides non-empty.
        let delta = EditDelta.compute(inserted: "we use Quinn three for ASR",
                                      userFinal: "we use Qwen3 for ASR")
        #expect(delta.substitutions == [WordSubstitution(from: "Quinn three", to: "Qwen3")])
    }

    @Test func wholesaleRewriteIsLargeModify() {
        let delta = EditDelta.compute(
            inserted: "今天我们讨论一下数据合规的问题",
            userFinal: "算了，换个完全不同的话题来说说人工智能伦理吧")
        #expect(delta.isLargeModify == true)
    }
}
