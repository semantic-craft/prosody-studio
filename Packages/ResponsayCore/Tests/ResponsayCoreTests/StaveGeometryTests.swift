import Testing
import Foundation
@testable import ResponsayCore

/// 144 v2 — per-lane toStave() geometry. Verification: tone shapes the whole lane,
/// stress lifts points, arrows present, app-side liaison, long sentence → lanes.
struct StaveGeometryTests {
    private func word(_ t: String, syllables: [String]? = nil, stressIndex: Int? = nil,
                      nuclear: Bool = false, ipa: String? = nil) -> Word {
        let syl = syllables ?? [t]
        return Word(text: t, syllables: syl, stressIndex: stressIndex,
                    stressed: stressIndex != nil, nuclear: nuclear, ipa: ipa, linkToNext: nil)
    }
    private func analysis(_ tone: Tone, _ words: [Word]) -> ProsodyAnalysis {
        ProsodyAnalysis(text: words.map(\.text).joined(separator: " "), isGeneratedExample: false,
                        sourceWord: nil, ipa: "", thoughtGroups: [ThoughtGroup(tone: tone, words: words)], notes: nil)
    }

    @Test func oneLanePerThoughtGroup() {
        let lanes = ProsodyStave.toStave(.holdsUp)
        #expect(lanes.count == 2)                 // long-sentence handling = stacked lanes
        #expect(lanes[0].toneArrow == "↘↗" || lanes[0].toneArrow == "→")
    }

    @Test func tokensCarrySyllableStress() {
        let lanes = ProsodyStave.toStave(analysis(.fall, [
            word("I'll"), word("call", stressIndex: 0, nuclear: true), word("you"),
        ]))
        let call = lanes[0].tokens.first { $0.text == "call" }
        #expect(call?.stressed == true)
        #expect(call?.nuclear == true)
        #expect(lanes[0].tokens.first { $0.text == "you" }?.reduced == true)  // stressIndex nil → reduced
    }

    @Test func repairedShapeFeedsRenderableToken() throws {
        let bad = analysis(.fall, [
            Word(text: "finish", syllables: [], stressIndex: nil,
                 stressed: true, nuclear: true, ipa: nil, linkToNext: nil),
        ])
        let repaired = try ProsodyValidator.repairProsodyShape(bad)
        let lanes = ProsodyStave.toStave(repaired)
        let token = try #require(lanes.first?.tokens.first)

        #expect(token.syllables == ["finish"])
        #expect(token.stressIndex == 0)
        #expect(token.reduced == false)
    }

    @Test func fallTone_descendsAcrossWholeLane() {
        let lanes = ProsodyStave.toStave(analysis(.fall, [
            word("one", stressIndex: 0), word("two", stressIndex: 0), word("three", stressIndex: 0, nuclear: true),
        ]))
        let pitches = lanes[0].points.map(\.pitch)
        #expect(pitches.first! > pitches.last!)   // whole lane trends down, not a nucleus-only wiggle
    }

    @Test func riseTone_ascendsAcrossWholeLane() {
        let lanes = ProsodyStave.toStave(analysis(.rise, [
            word("are"), word("you", stressIndex: 0, nuclear: true),
        ]))
        #expect(lanes[0].points.first!.pitch < lanes[0].points.last!.pitch)
        #expect(lanes[0].toneArrow == "↗")
    }

    @Test func levelTone_isFlatBeforeEmphasis() {
        let lanes = ProsodyStave.toStave(analysis(.level, [word("okay", syllables: ["o", "kay"], stressIndex: 1, nuclear: true)]))
        #expect(lanes[0].toneArrow == "→")
        #expect(lanes[0].points.count == 1)
    }

    @Test func stressLiftsPitchAboveReduced() {
        // a stressed word sits higher on the contour than a reduced one at the same progress.
        let lanes = ProsodyStave.toStave(analysis(.level, [
            word("the"), word("CAT", stressIndex: 0), word("sat"), word("DOWN", stressIndex: 0, nuclear: true),
        ]))
        let cat = lanes[0].points.first { $0.kind == .stressed }!
        let the = lanes[0].points.first { $0.kind == .reduced }!
        #expect(cat.pitch > the.pitch)
    }

    @Test func arrowsForAllTones() {
        #expect(ProsodyStave.arrows[.fall] == "↘")
        #expect(ProsodyStave.arrows[.rise] == "↗")
        #expect(ProsodyStave.arrows[.level] == "→")
    }

    @Test func appComputesLiaison_holdsUp() {
        // model linkToNext ignored; app derives liaison from /…z/ + /ʌ…/.
        let a = analysis(.fall, [
            word("holds", stressIndex: 0, ipa: "hoʊldz"), word("up", stressIndex: 0, nuclear: true, ipa: "ʌp"),
        ])
        let lanes = ProsodyStave.toStave(a)
        #expect(lanes[0].tokens[0].link == .liaison)
    }

    @Test func isDeterministic() {
        #expect(ProsodyStave.toStave(.holdsUp) == ProsodyStave.toStave(.holdsUp))
    }

    @Test func geometryDerivesFromModel_notProvidedCoords() {
        let words = [word("are"), word("you", stressIndex: 0, nuclear: true)]
        let fall = ProsodyStave.toStave(analysis(.fall, words))
        let rise = ProsodyStave.toStave(analysis(.rise, words))
        #expect(fall[0].points.map(\.pitch) != rise[0].points.map(\.pitch))
    }
}
