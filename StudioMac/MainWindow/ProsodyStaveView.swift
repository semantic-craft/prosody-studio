import SwiftUI
import ResponsayCore

/// 144 v2 — renders a `ProsodyAnalysis` as **B+C**: one warm-paper card per
/// thought group (C), each with faint staff grid lines (B), a tone-driven pitch
/// contour, stress beats, and a syllable-level word row. Geometry is computed
/// (`ProsodyStave.toStave`) — the model emits no coordinates. Long sentences
/// stack as lanes.
struct ProsodyStaveView: View {
    let analysis: ProsodyAnalysis
    /// Global word index currently spoken (drives highlight); `nil` = none.
    var activeWordIndex: Int?

    private var lanes: [StaveLane] { ProsodyStave.toStave(analysis) }

    /// Each lane with its global word offset, so a single utterance-wide index
    /// resolves to the right lane + token.
    private var laneInfos: [(offset: Int, base: Int, lane: StaveLane)] {
        var base = 0
        var infos: [(offset: Int, base: Int, lane: StaveLane)] = []
        for (index, lane) in lanes.enumerated() {
            infos.append((index, base, lane))
            base += lane.tokens.count
        }
        return infos
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(laneInfos, id: \.offset) { info in
                ProsodyLaneView(lane: info.lane, baseIndex: info.base, activeWordIndex: activeWordIndex)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("语调可视化:\(analysis.text)")
    }
}

private struct ProsodyLaneView: View {
    let lane: StaveLane
    var baseIndex: Int = 0
    var activeWordIndex: Int?

    private let plotHeight: CGFloat = 88
    private let wordBand: CGFloat = 56
    private let pad: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            badge
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        drawGrid(context, width: w)
                        drawContour(context, width: w)
                        drawBeats(context, width: w)
                    }
                    .frame(width: w, height: plotHeight)

                    ForEach(lane.tokens.indices, id: \.self) { index in
                        ProsodyWordView(token: lane.tokens[index],
                                        isActive: activeWordIndex == baseIndex + index)
                            .position(x: lane.points[index].x * w, y: plotHeight + wordBand / 2)
                    }
                    ForEach(linkAnchors(width: w), id: \.id) { anchor in
                        Text("‿").font(.system(size: 16)).foregroundStyle(SettingsTheme.cEng)
                            .position(x: anchor.x, y: plotHeight + 8)
                    }
                }
            }
            .frame(height: plotHeight + wordBand)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(SettingsTheme.card2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private var badge: some View {
        HStack(spacing: 5) {
            Text(lane.toneArrow).font(.system(size: 14, weight: .semibold))
            Text(lane.toneLabel).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(SettingsTheme.wine)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(SettingsTheme.wineTint))
    }

    // MARK: - Canvas layers

    private func y(_ pitch: Double) -> CGFloat {
        let top = pad, bottom = plotHeight - pad
        let norm = (pitch - 0.30) / (0.88 - 0.30)   // pitch range → 0…1
        return bottom - CGFloat(norm) * (bottom - top)
    }

    private func drawGrid(_ context: GraphicsContext, width: CGFloat) {
        for (pitch, strong) in [(0.84, false), (0.57, true), (0.34, false)] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(pitch)))
            line.addLine(to: CGPoint(x: width, y: y(pitch)))
            context.stroke(line, with: .color(strong ? SettingsTheme.hair : SettingsTheme.hair2),
                           style: StrokeStyle(lineWidth: 1, dash: strong ? [] : [2, 5]))
        }
    }

    private func drawContour(_ context: GraphicsContext, width: CGFloat) {
        let points = lane.points.map { CGPoint(x: $0.x * width, y: y($0.pitch)) }
        guard points.count > 1 else {
            if let p = points.first {
                let dot = Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(SettingsTheme.wine))
            }
            return
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let mid = CGPoint(x: (points[index - 1].x + points[index].x) / 2,
                              y: (points[index - 1].y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: points[index - 1])
        }
        path.addLine(to: points[points.count - 1])
        let shadow = path.offsetBy(dx: 0, dy: 1.4)   // soft drop shadow
        context.stroke(shadow, with: .color(.black.opacity(0.06)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        context.stroke(path, with: .color(SettingsTheme.wine),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
    }

    private func drawBeats(_ context: GraphicsContext, width: CGFloat) {
        for point in lane.points {
            let center = CGPoint(x: point.x * width, y: y(point.pitch))
            switch point.kind {
            case .nuclear:
                var diamond = Path()
                let r: CGFloat = 5
                diamond.move(to: CGPoint(x: center.x, y: center.y - r))
                diamond.addLine(to: CGPoint(x: center.x + r, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + r))
                diamond.addLine(to: CGPoint(x: center.x - r, y: center.y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(SettingsTheme.wine))
            case .stressed:
                let dot = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(SettingsTheme.card2))
                context.stroke(dot, with: .color(SettingsTheme.ink2), lineWidth: 1.6)
            case .reduced, .plain:
                break
            }
        }
    }

    private struct LinkAnchor: Identifiable { let id: Int; let x: CGFloat }

    private func linkAnchors(width: CGFloat) -> [LinkAnchor] {
        lane.tokens.indices.compactMap { index in
            guard lane.tokens[index].link != nil, index + 1 < lane.points.count else { return nil }
            let midX = (lane.points[index].x + lane.points[index + 1].x) / 2 * width
            return LinkAnchor(id: index, x: midX)
        }
    }
}

/// One word: syllables with the exact stressed syllable bold + `ˈ`, nuclear
/// enlarged/wine/underlined, reduced dimmed; mini-IPA underneath.
private struct ProsodyWordView: View {
    let token: StaveToken
    var isActive: Bool = false

    private var baseSize: CGFloat { token.nuclear ? 19 : token.reduced ? 14 : 16 }
    private var color: Color { token.nuclear ? SettingsTheme.wine : token.reduced ? SettingsTheme.ink3 : SettingsTheme.ink }

    var body: some View {
        content
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? SettingsTheme.wineTint2 : .clear)
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private var content: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(token.syllables.indices, id: \.self) { index in
                    Text(token.syllables[index])
                        .font(SettingsTheme.serif(baseSize, weight: index == token.stressIndex ? .heavy : .regular))
                        .overlay(alignment: .top) {
                            if index == token.stressIndex {
                                Text("ˈ").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(token.nuclear ? SettingsTheme.wine : SettingsTheme.ink2)
                                    .offset(y: -12)
                            }
                        }
                }
            }
            .foregroundStyle(color)
            .overlay(alignment: .bottom) {
                if token.nuclear {
                    Rectangle().fill(SettingsTheme.wine).frame(height: 2).offset(y: 2)
                }
            }
            if let ipa = token.ipa {
                Text("/\(ipa)/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(token.nuclear ? SettingsTheme.wine.opacity(0.8) : SettingsTheme.ink3)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
}
