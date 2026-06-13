import CoreGraphics
import Foundation

// MARK: - 070 Snap & Translate · OCR result model
//
// The structured output of any `OCRProvider`: the recognized text plus per-region
// geometry/confidence. `text` is the raw line-join (provider order, newline-separated);
// smart paragraphing / dual-run replacement (issues 073/074) layer on top of this — they
// do not change the shape. Pure value types (no AppKit), so Core stays iOS/macOS portable
// and the model is unit-testable without a screen.

/// Recognized text for one captured image.
public struct OCRResult: Sendable, Equatable {
    /// Raw per-line join in provider order, newline-separated. Paragraph reflow happens above.
    public let text: String
    /// Per-region text + pixel box + confidence (drives 073's image↔text highlight).
    public let regions: [OCRRegion]
    /// Recognition languages the provider was configured with (e.g. `["zh-Hans", "en-US"]`).
    public let languages: [String]

    public init(text: String, regions: [OCRRegion], languages: [String]) {
        self.text = text
        self.regions = regions
        self.languages = languages
    }

    /// Build a result from regions, joining their text in order. Keeps `text` and `regions`
    /// consistent so callers never hand-join.
    public init(regions: [OCRRegion], languages: [String]) {
        self.init(
            text: regions.map(\.text).joined(separator: "\n"),
            regions: regions,
            languages: languages)
    }

    /// True when nothing was recognized — callers degrade (no Coach hand-off, show guidance).
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One recognized line/box: text, pixel-space bounding box (origin top-left), confidence 0–1.
public struct OCRRegion: Sendable, Equatable {
    public let text: String
    /// Pixel-space box in the captured image (origin top-left; Y already flipped from Vision).
    public let boundingBox: CGRect
    /// Provider confidence for the top candidate, 0–1 (used by dual-run replacement, issue 074).
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}
