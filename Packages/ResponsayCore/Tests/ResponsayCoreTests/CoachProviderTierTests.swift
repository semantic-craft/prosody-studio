import Testing
import Foundation
@testable import ResponsayCore

/// 184 — `CoachProvider` (cloud | offline) + `CoachTier` (E4B | 12B) decode + default resolution.
/// Default provider is `.cloud` (offline is opt-in); default tier is `.e4b` (light/fast).
struct CoachProviderTierTests {
    @Test func provider_resolvesAndDefaultsToCloud() {
        #expect(CoachProvider.resolve(stored: "cloud") == .cloud)
        #expect(CoachProvider.resolve(stored: "offline") == .offline)
        #expect(CoachProvider.resolve(stored: "OFFLINE") == .offline)
        // Missing / blank / unknown all default to cloud (opt-in offline).
        #expect(CoachProvider.resolve(stored: nil) == .cloud)
        #expect(CoachProvider.resolve(stored: "") == .cloud)
        #expect(CoachProvider.resolve(stored: "bogus") == .cloud)
    }

    @Test func provider_tolerantDecode() throws {
        struct W: Decodable { let p: CoachProvider }
        #expect(try JSONDecoder().decode(W.self, from: #"{"p":"offline"}"#.data(using: .utf8)!).p == .offline)
        #expect(try JSONDecoder().decode(W.self, from: #"{"p":"nonsense"}"#.data(using: .utf8)!).p == .cloud)
    }

    @Test func tier_resolvesAndDefaultsToE4B() {
        #expect(CoachTier.resolve(stored: "e4b") == .e4b)
        #expect(CoachTier.resolve(stored: "12b") == .e4b)  // 12B tier removed → unknown falls back to E4B
        #expect(CoachTier.resolve(stored: "E4B") == .e4b)
        #expect(CoachTier.resolve(stored: nil) == .e4b)
        #expect(CoachTier.resolve(stored: "bogus") == .e4b)
    }

    @Test func tier_wireValuesMatchBackendTierTags() {
        // These raw values are what the backend's offlineCoachTierTag maps to Ollama tags.
        #expect(CoachTier.e4b.rawValue == "e4b")
    }

    @Test func roundTripsEachValue() {
        for p in CoachProvider.allCases { #expect(CoachProvider.resolve(stored: p.rawValue) == p) }
        for t in CoachTier.allCases { #expect(CoachTier.resolve(stored: t.rawValue) == t) }
    }
}
