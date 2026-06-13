import SwiftUI
import ResponsayCore

/// 146 — word + pitch feedback card for the pronunciation screen follow-read loop.
/// 303 — the card is no longer a dead end: 「存入复习」 banks the sentence into
/// the studio's SM-2 queue, 「练错词」 banks it AND jumps to the 练习室.
struct FollowReadFeedbackView: View {
    let feedback: SpeechFeedback
    var onRetry: () -> Void
    /// Returns true when the sentence was banked (false = perfect read, nothing to save).
    var onSaveForReview: (() -> Bool)? = nil
    var onDrillMistakes: (() -> Void)? = nil

    @State private var savedForReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("跟读反馈").font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
                Spacer()
                if let onSaveForReview {
                    Button(savedForReview ? "已存入复习" : "存入复习") {
                        savedForReview = onSaveForReview() || savedForReview
                    }
                    .controlSize(.small)
                    .disabled(savedForReview)
                    .help("把这句存进练习室的间隔复习队列（SM-2）")
                }
                if let onDrillMistakes {
                    Button("练错词", action: onDrillMistakes).controlSize(.small)
                        .help("把这句的差距记成错题并打开练习室")
                }
                Button("再练一次", action: onRetry).controlSize(.small)
            }
            Text(feedback.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SettingsTheme.ink)
            if !feedback.recognizedText.isEmpty {
                Text("识别：\(feedback.recognizedText)")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.ink2)
            }
            ProgressView(value: feedback.similarity)
                .tint(SettingsTheme.wine)

            if let pitch = feedback.pitchFeedback {
                Rectangle().fill(SettingsTheme.hair2).frame(height: 1).padding(.vertical, 2)
                Text(pitch.message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)
                // 306: 示范 vs 你的 double-curve overlay. Geometry is computed in
                // core (PitchOverlayGeometry); nil (unusable curves) degrades to
                // the text-only rows below — no empty axes. Drawn statically:
                // there is no animation branch at all, so Reduce Motion needs
                // no special casing.
                if let overlay = PitchOverlayGeometry.overlay(
                    target: pitch.targetCurve, learner: pitch.learnerCurve) {
                    pitchOverlay(overlay)
                }
                HStack(spacing: 12) {
                    Label("示范 \(trendLabel(pitch.targetTrend))", systemImage: "target")
                    Label("你的 \(trendLabel(pitch.learnerTrend))", systemImage: "waveform.path")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsTheme.ink2)
                ProgressView(value: pitch.similarity)
                    .tint(SettingsTheme.wine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("跟读反馈")
    }

    /// 306 — thin renderer: maps the core's unit-space polylines onto the
    /// Canvas rect. Target = theme red, learner = ink stroke; legend inline.
    private func pitchOverlay(
        _ overlay: (target: [PitchOverlayPoint], learner: [PitchOverlayPoint])
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                func path(_ points: [PitchOverlayPoint]) -> Path {
                    var p = Path()
                    for (i, pt) in points.enumerated() {
                        // y is pitch height (1 = high) → flip into view space.
                        let v = CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
                        if i == 0 { p.move(to: v) } else { p.addLine(to: v) }
                    }
                    return p
                }
                let mid = Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                context.stroke(mid, with: .color(SettingsTheme.hair2), lineWidth: 1)
                context.stroke(path(overlay.target), with: .color(SettingsTheme.wine),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                context.stroke(path(overlay.learner), with: .color(SettingsTheme.ink2),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                                  dash: [4, 3]))
            }
            .frame(height: 56)
            .accessibilityLabel("音高曲线对比：红色实线是示范，灰色虚线是你的发音")
            HStack(spacing: 10) {
                Label("示范", systemImage: "minus").foregroundStyle(SettingsTheme.wine)
                Label("你的", systemImage: "ellipsis").foregroundStyle(SettingsTheme.ink2)
            }
            .font(.system(size: 10, weight: .medium))
        }
    }

    private func trendLabel(_ trend: String) -> String {
        switch trend {
        case "rise": "升调"
        case "fall": "降调"
        case "level": "平调"
        default: "未知"
        }
    }
}