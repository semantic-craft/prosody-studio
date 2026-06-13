import SwiftUI
import ResponsayCore

/// Signature feature: a sentence becomes a readable melody line.
/// Data = `ProsodyAnalysis`; this view renders, it does not analyze.
struct ProsodyView: View {
    let analysis: ProsodyAnalysis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(Array(analysis.thoughtGroups.enumerated()), id: \.offset) { _, group in
                MelodyLine(group: group, progress: drawn ? 1 : 0)
            }
            footer
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .onAppear {
            if reduceMotion { drawn = true }
            else { withAnimation(.easeOut(duration: 0.9)) { drawn = true } }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                Text(analysis.ipa).font(.system(.footnote, design: .monospaced))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let notes = analysis.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - One thought group as a melody line

private struct MelodyLine: View {
    let group: ThoughtGroup
    var progress: CGFloat

    private let amp: CGFloat = 28
    private let rowPad: CGFloat = 24
    private static let space = "melody"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(Array(group.words.enumerated()), id: \.offset) { i, w in
                WordChip(word: w)
                    .offset(y: -amp * (ProsodyMath.pitch(group: group, index: i) - 0.5))
                    .opacity((w.stressed ? 1.0 : 0.5) * Double(max(0.2, progress)))
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: FramesKey.self,
                                value: [i: g.frame(in: .named(Self.space))]
                            )
                        }
                    )
            }
        }
        .padding(.vertical, rowPad)
        .padding(.horizontal, 4)
        .coordinateSpace(.named(Self.space))
        .backgroundPreferenceValue(FramesKey.self) { frames in
            decoration(frames)
        }
    }

    private func decoration(_ frames: [Int: CGRect]) -> some View {
        let baseline = frames.values.first?.midY ?? rowPad
        func point(_ i: Int) -> CGPoint? {
            guard let f = frames[i] else { return nil }
            let cy = baseline - amp * (ProsodyMath.pitch(group: group, index: i) - 0.5)
            return CGPoint(x: f.midX, y: cy + f.height / 2 + 4)   // wave sits just UNDER each word
        }
        let pts: [CGPoint] = (0..<group.words.count).compactMap(point)

        return ZStack {
            MelodyShape(points: pts)
                .trim(from: 0, to: progress)
                .stroke(
                    ProsodyPalette.line,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

            ForEach(Array(group.words.enumerated()), id: \.offset) { i, w in
                if w.nuclear, let p = point(i) {
                    Circle()
                        .fill(ProsodyPalette.accent)
                        .frame(width: 9, height: 9)
                        .position(p)
                        .scaleEffect(progress)
                        .opacity(progress)
                }
            }

            ForEach(Array(group.words.enumerated()), id: \.offset) { i, w in
                if w.linkToNext != nil,
                   let from = frames[i],
                   let to = frames[i + 1] {
                    LinkArc(
                        start: CGPoint(x: from.maxX + 2, y: max(from.maxY, to.maxY) + 8),
                        end: CGPoint(x: to.minX - 2, y: max(from.maxY, to.maxY) + 8))
                    .trim(from: 0, to: progress)
                    .stroke(
                        ProsodyPalette.link,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4])
                    )
                    .accessibilityLabel("连读")
                }
            }
        }
    }
}

// MARK: - A word, with syllable-level stress

private struct WordChip: View {
    let word: ProsodyWord

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.syllables.enumerated()), id: \.offset) { idx, syl in
                Text(syl)
                    .fontWeight(weight(idx))
                    .foregroundStyle(color(idx))
            }
        }
        .font(.system(.body, design: .rounded))
    }

    private func weight(_ idx: Int) -> Font.Weight {
        guard word.stressed else { return .regular }
        return idx == word.stressIndex ? .heavy : .medium
    }

    private func color(_ idx: Int) -> Color {
        if word.nuclear { return ProsodyPalette.accent }
        return word.stressed ? .primary : .secondary
    }
}

// MARK: - Helpers

private enum ProsodyPalette {
    static let line = Theme.prosody      // was Theme.stress (coral)
    static let accent = Theme.prosody    // nuclear stress dot/word; was Theme.accent
    static let link = Color.secondary.opacity(0.55)
}

private enum ProsodyMath {
    /// Normalized pitch 0 (low) … 1 (high), shaped by the group's tone after the nuclear word.
    static func pitch(group: ThoughtGroup, index: Int) -> CGFloat {
        let words = group.words
        guard let nucleusPos = words.firstIndex(where: { $0.nuclear }) else {
            return words[index].stressed ? 0.6 : 0.4
        }
        if index < nucleusPos { return words[index].stressed ? 0.62 : 0.42 }
        let tail = words.count - 1 - nucleusPos
        let k = tail <= 0 ? 0 : CGFloat(index - nucleusPos) / CGFloat(tail)
        switch group.tone {
        case .fall:     return 0.82 - 0.55 * k
        case .rise:     return 0.42 + 0.45 * k
        case .level:    return 0.55
        case .fallRise: return k < 0.5 ? 0.64 - 0.30 * (k / 0.5) : 0.34 + 0.46 * ((k - 0.5) / 0.5)
        case .riseFall: return k < 0.5 ? 0.55 + 0.30 * (k / 0.5) : 0.85 - 0.55 * ((k - 0.5) / 0.5)
        }
    }
}

private struct MelodyShape: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        if points.count == 1 {
            p.addLine(to: CGPoint(x: first.x + 0.5, y: first.y))
            return p
        }
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2,
                              y: (points[i - 1].y + points[i].y) / 2)
            p.addQuadCurve(to: mid, control: points[i - 1])
            if i == points.count - 1 { p.addLine(to: points[i]) }
        }
        return p
    }
}

private struct LinkArc: Shape {
    var start: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 12)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

private struct FramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#Preview {
    ProsodyView(analysis: .sample).padding()
}
