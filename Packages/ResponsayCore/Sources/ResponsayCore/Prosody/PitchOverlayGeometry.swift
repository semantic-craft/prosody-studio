import Foundation

/// One polyline point in normalized overlay space — both axes 0…1, y clamped.
public struct PitchOverlayPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 306 — pure geometry for the「示范曲线 vs 你的曲线」overlay. Consumes the
/// normalized pitch curves the comparator already computes; the view only maps
/// these unit-space polylines onto its Canvas size. Alignment is **time-axis
/// normalization** (both curves resampled onto a shared 0…1 time axis) — the
/// issue's "DTW 路径已有" turned out false (dtwDistance keeps no backtracking
/// path), and warping the learner's time axis would misrepresent their actual
/// timing anyway; DTW stays what it was: the similarity score.
public enum PitchOverlayGeometry {
    /// Min-max normalize to 0…1 preserving order. Non-finite values are
    /// dropped; a constant curve maps to 0.5 (mid-stave).
    public static func normalize01(_ points: [Double]) -> [Double] {
        let finite = points.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else { return [] }
        let span = hi - lo
        guard span > 0.0001 else { return Array(repeating: 0.5, count: finite.count) }
        return finite.map { ($0 - lo) / span }
    }

    /// Linear resample onto `count` evenly spaced samples over the curve's
    /// own 0…1 time axis. Fewer than 2 input points cannot define a curve.
    public static func resample(_ points: [Double], to count: Int) -> [Double] {
        guard points.count >= 2, count >= 2 else { return [] }
        let last = points.count - 1
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1) * Double(last)
            let lower = Int(t.rounded(.down))
            let upper = min(lower + 1, last)
            let frac = t - Double(lower)
            return points[lower] * (1 - frac) + points[upper] * frac
        }
    }

    /// Overlay polylines for the two curves on a shared normalized time axis.
    /// Returns nil when either curve has fewer than 2 finite points — the
    /// caller degrades to the text-only card (no empty axes).
    public static func overlay(
        target: [Double],
        learner: [Double],
        samples: Int = 48
    ) -> (target: [PitchOverlayPoint], learner: [PitchOverlayPoint])? {
        let t = resample(normalize01(target), to: samples)
        let l = resample(normalize01(learner), to: samples)
        guard !t.isEmpty, !l.isEmpty else { return nil }
        func polyline(_ ys: [Double]) -> [PitchOverlayPoint] {
            ys.enumerated().map { i, y in
                PitchOverlayPoint(
                    x: Double(i) / Double(ys.count - 1),
                    y: min(1, max(0, y)))
            }
        }
        return (polyline(t), polyline(l))
    }
}
