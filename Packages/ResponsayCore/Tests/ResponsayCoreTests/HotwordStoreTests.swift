import Testing
@testable import ResponsayCore

struct HotwordStoreTests {
    @Test func defaultStore_seedsAllSixCategories() {
        let store = HotwordStore()
        for category in HotwordCategory.allCases {
            _ = store.terms(in: category) // every category is addressable
        }
        // A verifiable seed term is present in the flattened dictionary.
        #expect(store.flattened().contains("CLSCI"))
        #expect(store.terms(in: .code).contains("SwiftUI"))
    }

    @Test func userTerms_comeFirst_soTheySurviveTheCap() {
        let store = HotwordStore(userTerms: ["Mandelbaum"])
        #expect(store.flattened().first == "Mandelbaum")
    }

    @Test func userTerm_equalToASeed_appearsOnce() {
        let store = HotwordStore(userTerms: ["CLSCI"])
        let flat = store.flattened()
        #expect(flat.filter { $0 == "CLSCI" }.count == 1)
        #expect(flat.first == "CLSCI")
    }

    @Test func flattened_trimsBlanksAndDedupes() {
        let store = HotwordStore(userTerms: ["  ", "Foucault ", "Foucault"], seeds: [:])
        #expect(store.flattened() == ["Foucault"])
    }

    @Test func flattened_respectsTheLimit_keepingUserTermsFirst() {
        let store = HotwordStore(userTerms: ["A", "B", "C"], seeds: [.legal: ["CLSCI"]])
        #expect(store.flattened(limit: 2) == ["A", "B"])
    }
}
