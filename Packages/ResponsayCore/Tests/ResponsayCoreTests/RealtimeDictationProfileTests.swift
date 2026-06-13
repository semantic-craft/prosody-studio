import Testing
import Foundation
@testable import ResponsayCore

/// Maps a dictation profile to the Qwen realtime VAD config (spec
/// `2026-06-06-imk-xpc-voice-engine.md` §4). Threshold/silence stay within the
/// verified ranges from the DashScope client-events doc (threshold [-1,1],
/// silence [200,6000]); `pushToTalk` disables VAD (Manual mode → turnDetection nil).
@Suite struct RealtimeDictationProfileTests {
    @Test func quickMessageUsesResponsiveServerVAD() {
        #expect(RealtimeDictationProfile.quickMessage.turnDetection
                == RealtimeTurnDetection(threshold: 0.0, silenceDurationMs: 400))
    }

    @Test func legalWritingUsesManualModeSoSentencesAreNeverSplit() {
        // Manual mode (turn_detection nil): the client endpoints at stop, so the
        // server never splits a legal/academic sentence at an in-sentence pause.
        #expect(RealtimeDictationProfile.legalWriting.turnDetection == nil)
    }

    @Test func commandIsSnappy() {
        #expect(RealtimeDictationProfile.command.turnDetection
                == RealtimeTurnDetection(threshold: 0.0, silenceDurationMs: 400))
    }

    @Test func pushToTalkSelectsManualMode() {
        #expect(RealtimeDictationProfile.pushToTalk.turnDetection == nil)
    }
}
