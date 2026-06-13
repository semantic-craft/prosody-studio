import Testing
import Foundation
@testable import ResponsayCore

// 306 — pure overlay geometry: the curves that reach the card are exactly the
// comparator's normalized curves, resampled onto a shared unit time axis.

struct PitchOverlayGeometryTests {
    // MARK: normalize01

    @Test func normalize_mapsRangeToUnit_andKeepsOrder() {
        let out = PitchOverlayGeometry.normalize01([100, 150, 200])
        #expect(out == [0, 0.5, 1])
    }

    @Test func normalize_constantCurve_mapsToMidline() {
        #expect(PitchOverlayGeometry.normalize01([220, 220, 220]) == [0.5, 0.5, 0.5])
    }

    @Test func normalize_dropsNonFinite() {
        let out = PitchOverlayGeometry.normalize01([.nan, 100, .infinity, 200])
        #expect(out == [0, 1])
    }

    @Test func normalize_empty_isEmpty() {
        #expect(PitchOverlayGeometry.normalize01([]).isEmpty)
    }

    // MARK: resample

    @Test func resample_singlePointOrEmpty_cannotDefineACurve() {
        #expect(PitchOverlayGeometry.resample([], to: 10).isEmpty)
        #expect(PitchOverlayGeometry.resample([0.4], to: 10).isEmpty)
    }

    @Test func resample_preservesEndpoints_andInterpolatesLinearly() {
        let out = PitchOverlayGeometry.resample([0, 1], to: 5)
        #expect(out == [0, 0.25, 0.5, 0.75, 1])
    }

    @Test func resample_downsamplesLongCurve() {
        let long = (0...100).map(Double.init)
        let out = PitchOverlayGeometry.resample(long, to: 3)
        #expect(out == [0, 50, 100])
    }

    // MARK: overlay

    @Test func overlay_unequalLengths_shareOneTimeAxis() throws {
        let geo = try #require(PitchOverlayGeometry.overlay(
            target: [0.2, 0.8],                       // 2 points
            learner: (0..<37).map { Double($0) },     // 37 points
            samples: 24))
        #expect(geo.target.count == 24)
        #expect(geo.learner.count == 24)
        #expect(geo.target.first?.x == 0)
        #expect(geo.target.last?.x == 1)
        #expect(geo.learner.first?.x == 0)
        #expect(geo.learner.last?.x == 1)
    }

    @Test func overlay_extremeValues_neverLeaveUnitBox() throws {
        let geo = try #require(PitchOverlayGeometry.overlay(
            target: [-1e9, 0, 1e9], learner: [5_000, -5_000], samples: 16))
        for pt in geo.target + geo.learner {
            #expect(pt.y >= 0 && pt.y <= 1)
            #expect(pt.x >= 0 && pt.x <= 1)
        }
    }

    @Test func overlay_emptyOrSinglePointCurve_returnsNil() {
        #expect(PitchOverlayGeometry.overlay(target: [], learner: [0.1, 0.2]) == nil)
        #expect(PitchOverlayGeometry.overlay(target: [0.1, 0.2], learner: [0.3]) == nil)
        #expect(PitchOverlayGeometry.overlay(target: [], learner: []) == nil)
    }

    // MARK: feedback plumbing (the curves actually travel)

    @Test func comparator_carriesNormalizedCurvesIntoFeedback() {
        let feedback = PitchContourComparator.evaluate(
            target: PitchContour(points: [100, 150, 200]),
            learner: PitchContour(points: [220, 180, 140, 120]))
        #expect(feedback.targetCurve == [0, 0.5, 1])
        #expect(feedback.learnerCurve.count == 4)
        #expect(feedback.learnerCurve.first == 1)   // normalized, descending
        #expect(feedback.learnerCurve.last == 0)
    }

    @Test func comparator_insufficientData_leavesCurvesEmpty() {
        let feedback = PitchContourComparator.evaluate(
            target: PitchContour(points: [100]),
            learner: PitchContour(points: []))
        #expect(feedback.targetCurve.isEmpty)
        #expect(feedback.learnerCurve.isEmpty)
        // …and the overlay correctly refuses to draw an axis for it.
        #expect(PitchOverlayGeometry.overlay(
            target: feedback.targetCurve, learner: feedback.learnerCurve) == nil)
    }

    @Test func pitchFeedback_decodesLegacyPayloadWithoutCurves() throws {
        let legacy = #"{"similarity":0.5,"targetTrend":"rise","learnerTrend":"fall","message":"m"}"#
        let decoded = try JSONDecoder().decode(PitchFeedback.self, from: Data(legacy.utf8))
        #expect(decoded.targetCurve.isEmpty)
        #expect(decoded.learnerCurve.isEmpty)
        #expect(decoded.similarity == 0.5)
    }
}
