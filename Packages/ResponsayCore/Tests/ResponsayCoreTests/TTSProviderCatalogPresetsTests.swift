import Testing
import Foundation
@testable import ResponsayCore

/// 196 — cloud TTS provider catalog data. Test standard T1.
struct TTSProviderCatalogPresetsTests {
    @Test func everyCatalogResolvesItsDefaults() {
        for catalog in TTSProviderCatalogPresets.all {
            #expect(!catalog.voices.isEmpty)
            #expect(!catalog.models.isEmpty)
            #expect(catalog.defaultModel != nil, "\(catalog.providerID) default model dangles")
            #expect(catalog.defaultVoice != nil, "\(catalog.providerID) default voice dangles")
        }
    }

    @Test func lookupByProviderID() {
        #expect(TTSProviderCatalogPresets.catalog(for: "openai")?.providerID == "openai")
        #expect(TTSProviderCatalogPresets.catalog(for: "qwen")?.providerID == "qwen")
        #expect(TTSProviderCatalogPresets.catalog(for: "minimax")?.providerID == "minimax")
        #expect(TTSProviderCatalogPresets.catalog(for: "nope") == nil)
    }

    @Test func doubaoDefaultModelIsTTSResourceID() {
        #expect(TTSProviderCatalogPresets.doubao.defaults.modelID == "seed-tts-2.0")
        #expect(TTSProviderCatalogPresets.doubao.defaultModel?.id == "seed-tts-2.0")
    }

    @Test func doubaoVoicesUseOfficialModel2VoiceTypes() {
        let voices = TTSProviderCatalogPresets.doubao.voices
        let ids = Set(voices.map(\.id))

        #expect(ids.contains("en_female_dacey_uranus_bigtts"))
        #expect(ids.contains("en_male_tim_uranus_bigtts"))
        #expect(ids.contains("en_female_stokie_uranus_bigtts"))
        #expect(ids.contains("zh_female_vv_uranus_bigtts"))
        #expect(ids.contains("zh_female_xiaohe_uranus_bigtts"))
        #expect(ids.contains("zh_male_m191_uranus_bigtts"))
        #expect(!ids.contains("BV051_streaming"))
        #expect(!ids.contains("BV002_streaming"))
        #expect(!ids.contains("BV001_streaming"))
        #expect(voices.contains { $0.languageHints.contains("en-US") })
        #expect(voices.contains { $0.languageHints.contains("zh") })
    }

    @Test func codableRoundTrip() throws {
        let catalog = TTSProviderCatalogPresets.qwen
        let decoded = try JSONDecoder().decode(
            TTSProviderCatalog.self, from: JSONEncoder().encode(catalog))
        #expect(decoded == catalog)
    }

    @Test func qwenDefaultsToRealtimeAndIncludesRequestedVoices() {
        let catalog = TTSProviderCatalogPresets.qwen
        let ids = Set(catalog.voices.map(\.id))

        #expect(catalog.defaults.modelID == "qwen3-tts-flash-realtime")
        #expect(catalog.defaultModel?.supportsRealtimeWS == true)
        for required in ["Jennifer", "Ryan", "Maia", "Kai", "Neil", "Ono Anna", "Roy", "Peter", "Sunny"] {
            #expect(ids.contains(required), "missing Qwen voice \(required)")
        }
    }

    @Test func minimaxVoicesCoverOfficialMultilingualPreset() {
        let voices = TTSProviderCatalogPresets.minimax.voices
        let ids = Set(voices.map(\.id))

        for required in [
            "English_Trustworthy_Man", "English_Graceful_Lady",
            "German_FriendlyMan", "German_SweetLady",
            "French_Male_Speech_New", "French_MovieLeadFemale",
            "Japanese_IntellectualSenior", "Japanese_DecisivePrincess",
            "Korean_SweetGirl", "Korean_CheerfulBoyfriend",
        ] {
            #expect(ids.contains(required), "missing MiniMax voice \(required)")
        }
        #expect(voices.filter { $0.languageHints.contains("de") }.count >= 2)
        #expect(voices.filter { $0.languageHints.contains("en") }.count >= 2)
        #expect(voices.filter { $0.languageHints.contains("zh") }.count >= 2)
    }

    @Test func noProviderClaimsWordTiming() {
        // None of the surveyed cloud TTS APIs return word timing → highlight uses the
        // proportional aligner. Guard against a future preset over-promising.
        for catalog in TTSProviderCatalogPresets.all {
            for model in catalog.models {
                #expect(!model.supportsWordTiming, "\(catalog.providerID)/\(model.id)")
            }
        }
    }

    @Test func onlyQwenAdvertisesRealtimeStreaming() {
        let streaming = TTSProviderCatalogPresets.all
            .filter { $0.models.contains { $0.supportsRealtimeWS } }
            .map(\.providerID)
        #expect(streaming == ["doubao", "qwen"])
    }
}
