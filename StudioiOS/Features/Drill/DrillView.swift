import SwiftUI
import ResponsayCore

/// FSI repeat loop. Playback will later bind these commands to TTS audio.
struct DrillView: View {
    @State private var model = DrillViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    statusCard
                    transportCard
                    modeCard
                    rangeCard
                    eventsCard
                }
                .padding(Theme.Space.l)
                .safeAreaPadding(.bottom, 64)
            }
            .background(Theme.surface)
            .navigationTitle("操练")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .accessibilityLabel("停止复读")
                    .disabled(model.state.phase == .idle)
                }
            }
            .onChange(of: model.speed) { _, value in
                model.updateSpeed(value)
            }
            .onChange(of: model.abStart) { _, _ in
                model.normalizeABRange()
            }
            .onChange(of: model.abEnd) { _, _ in
                model.normalizeABRange()
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Label(model.statusTitle, systemImage: model.statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.statusColor)
                Spacer()
                Text(model.roundText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(model.currentText)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: model.roundProgress)
                .tint(Theme.accent)

            HStack {
                Text(model.rangeText)
                Spacer()
                Text(model.speedText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Picker("模式", selection: $model.mode) {
                Text("句子").tag(RepeatMode.sentence)
                Text("AB").tag(RepeatMode.ab)
                Text("全文").tag(RepeatMode.full)
            }
            .pickerStyle(.segmented)

            Stepper("轮次 \(model.count)", value: $model.count, in: 1...9)
            Stepper("间隔 \(model.timeLabel(model.interval))", value: $model.interval, in: 0...5, step: 0.5)
            Stepper("速度 \(model.speedText)", value: $model.speed, in: 0.5...2.0, step: 0.25)

            if model.mode == .sentence {
                Toggle("自动下一句", isOn: $model.autoAdvance)
            }
        }
        .card()
    }

    @ViewBuilder
    private var rangeCard: some View {
        switch model.mode {
        case .ab:
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Stepper("A 点 \(model.timeLabel(model.abStart))", value: $model.abStart, in: 0...12, step: 0.2)
                Stepper("B 点 \(model.timeLabel(model.abEnd))", value: $model.abEnd, in: 0.2...12, step: 0.2)
            }
            .card()
        case .sentence:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(model.sentences) { sentence in
                    Button {
                        model.selectedSentenceIndex = sentence.index
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text("\(sentence.index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(model.selectedSentenceIndex == sentence.index ? Theme.accent : .secondary)
                            Text(sentence.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(model.rangeLabel(for: sentence))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .fill(model.selectedSentenceIndex == sentence.index ? Theme.accent.opacity(0.12) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        case .full:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(model.fullText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.fullRangeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private var transportCard: some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                model.start()
            } label: {
                Label(model.state.phase == .idle ? "播放" : "重播", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Theme.controlRadius))
            .tint(Theme.accent)
            .foregroundStyle(Theme.accentInk)

            Button {
                model.completeSegment()
            } label: {
                Label("下一步", systemImage: "forward.end.fill")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: Theme.controlRadius))
            .disabled(model.state.phase != .playing && model.state.phase != .waiting)

            Button {
                model.togglePause()
            } label: {
                Label(model.state.phase == .paused ? "继续" : "暂停",
                      systemImage: model.state.phase == .paused ? "playpause.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: Theme.controlRadius))
            .disabled(model.state.phase != .playing && model.state.phase != .paused)
        }
        .card()
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("事件")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.events, id: \.self) { event in
                Text(event)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

#Preview {
    DrillView()
}
