import SwiftUI
import ResponsayCore

/// 发音纠正 — the prosody surface. Shows the signature stave (intonation + stress
/// + linking) for a sentence, rendered geometrically from `ProsodyAnalysis` (144).
/// 146: 跟读 = play reference → record → word + pitch feedback.
struct PronunciationScreen: View {
    /// 125 — an optional sentence seeded from selected / rewritten text (the selection→跟读
    /// bridge). When present it leads the picker and is selected on arrival; the canned samples
    /// stay as fallback practice material.
    var seed: ProsodyAnalysis?

    private let samples: [(title: String, analysis: ProsodyAnalysis)] = [
        ("I'm not sure that conclusion holds up.", .holdsUp),
        ("I'll call you.", .sample),
    ]
    @State private var index = 0
    @State private var reader = ReadAloudController()
    @State private var followRead = FollowReadSessionController()
    @State private var practiceRecorder = PracticeSpeechRecorder()
    @AppStorage("practiceSpeed") private var practiceSpeedRaw = "0.9"

    /// Speaking-rate options offered in the read-aloud transport (issue 198).
    private static let speedChoices: [Double] = [0.5, 0.75, 0.9, 1.0, 1.25, 1.5, 2.0]

    /// Picker contents: the seeded sentence (if any) leads, then the canned samples.
    private var sentences: [(title: String, analysis: ProsodyAnalysis)] {
        guard let seed, !seed.thoughtGroups.isEmpty else { return samples }
        let title = seed.text.isEmpty ? "跟读句" : seed.text
        return [(title, seed)] + samples
    }

    private var current: ProsodyAnalysis {
        let items = sentences
        return items.indices.contains(index) ? items[index].analysis : items[0].analysis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    staveCard
                    legend
                }
                .padding(22)
            }
        }
        .background(SettingsTheme.bg)
        .onAppear { reader.speed = Double(practiceSpeedRaw) ?? 0.9 }
        .onChange(of: practiceSpeedRaw) { reader.speed = Double(practiceSpeedRaw) ?? 0.9 }
        .onChange(of: index) { resetFollowRead(); reader.stop() }
        // 125 — a fresh seed leads the picker; jump to it and reset any in-flight follow-read.
        .onChange(of: seed?.text) { index = 0; resetFollowRead(); reader.stop() }
        .onDisappear { resetFollowRead(); reader.stop() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("发音纠正").font(.system(size: 22, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
                Text("听原声 → 跟读 → 复读，标升降调 / 重音 / 连读")
                    .font(.system(size: 12.5)).foregroundStyle(SettingsTheme.ink2)
            }
            Spacer()
            Picker("", selection: $index) {
                ForEach(sentences.indices, id: \.self) { Text(sentences[$0].title).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 280)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(SettingsTheme.hair).frame(height: 1) }
    }

    private var staveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(current.text)
                .font(SettingsTheme.serif(20, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
            if !current.ipa.isEmpty {
                Text(current.ipa).font(SettingsTheme.mono).foregroundStyle(SettingsTheme.ink3)
            }
            ProsodyStaveView(analysis: current, activeWordIndex: reader.activeIndex)
                .padding(.vertical, 4)
            if let notes = current.notes {
                Text(notes).font(.system(size: 12.5)).foregroundStyle(SettingsTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            transport
            followReadStatus
            if let feedback = followRead.feedback, case .feedback = followRead.phase {
                FollowReadFeedbackView(
                    feedback: feedback,
                    onRetry: { retryFollowRead() },
                    // 303: bank into the studio's SM-2 queue; perfect reads bank nothing.
                    onSaveForReview: { bankFollowReadMistake(feedback) },
                    onDrillMistakes: {
                        _ = bankFollowReadMistake(feedback)
                        NotificationCenter.default.post(name: .init("OpenStudioScreen"), object: nil)
                    })
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }

    private var isReading: Bool { reader.isPlaying && reader.mode == .reading }

    private var transport: some View {
        HStack(spacing: 8) {
            Button { reader.toggleRead(current) } label: {
                Label(isReading ? "暂停" : "朗读原声", systemImage: isReading ? "pause.fill" : "speaker.wave.2")
            }
            .buttonStyle(.borderedProminent).controlSize(.small).tint(SettingsTheme.wine)
            .disabled(followReadActive)
            Button { Task { await handleFollowReadTap() } } label: {
                Label(followReadButtonTitle, systemImage: followReadButtonIcon)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .tint(followReadRecording ? .red : SettingsTheme.wine)
            .disabled(followReadButtonDisabled)
            .help("先听示范，再录你的跟读；需要麦克风权限")
            Button { reader.repeatRead(current) } label: { Label("复读", systemImage: "repeat") }
                .controlSize(.small)
                .disabled(followReadActive)
            if reader.isPlaying || followReadActive {
                Button { stopAllPlayback() } label: { Label("停止", systemImage: "stop.fill") }.controlSize(.small)
            }
            speedMenu
            Spacer()
            Text("朗读 · Kokoro 本地；跟读识别走云端")
                .font(.system(size: 11)).foregroundStyle(SettingsTheme.ink3)
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var followReadStatus: some View {
        switch followRead.phase {
        case .playingReference:
            Label("正在播放示范…", systemImage: "speaker.wave.2")
                .font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink2)
        case .recording:
            Label("请跟读…点「停止跟读」结束", systemImage: "mic.fill")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(SettingsTheme.wine)
        case .processing:
            Label("识别跟读中…", systemImage: "ellipsis")
                .font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink2)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11.5)).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var followReadActive: Bool {
        switch followRead.phase {
        case .idle, .feedback: false
        default: true
        }
    }

    private var followReadRecording: Bool {
        if case .recording = followRead.phase { return true }
        return false
    }

    private var followReadButtonDisabled: Bool {
        switch followRead.phase {
        case .playingReference, .processing: true
        default: false
        }
    }

    private var followReadButtonTitle: String {
        switch followRead.phase {
        case .recording: "停止跟读"
        case .processing: "识别中…"
        case .playingReference: "播放示范…"
        default: "跟读"
        }
    }

    private var followReadButtonIcon: String {
        switch followRead.phase {
        case .recording: "stop.fill"
        case .processing: "ellipsis"
        default: "mic"
        }
    }

    /// 语速 selector (issue 198) — persists to `practiceSpeed`, applied at synthesis.
    private var speedMenu: some View {
        Menu {
            ForEach(Self.speedChoices, id: \.self) { rate in
                Button {
                    practiceSpeedRaw = String(rate)
                } label: {
                    if abs((Double(practiceSpeedRaw) ?? 0.9) - rate) < 0.001 {
                        Label(speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(rate))
                    }
                }
            }
        } label: {
            Label("语速 \(speedLabel(Double(practiceSpeedRaw) ?? 0.9))", systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
        .disabled(followReadActive)
    }

    private func speedLabel(_ rate: Double) -> String {
        rate == 1.0 ? "1.0×" : String(format: "%g×", rate)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(symbol: "ˈ", color: SettingsTheme.ink2, label: "重读音节")
            legendItem(symbol: "◆", color: SettingsTheme.wine, label: "核心重音")
            legendItem(symbol: "○", color: SettingsTheme.ink2, label: "次重音")
            legendItem(symbol: "↘↗→", color: SettingsTheme.wine, label: "升降调")
            legendItem(symbol: "‿", color: SettingsTheme.cEng, label: "连读")
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(symbol: String? = nil, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Text(symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            } else {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 2.5)
            }
            Text(label).font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink2)
        }
    }

    // MARK: - Follow-read (146)

    private func handleFollowReadTap() async {
        switch followRead.phase {
        case .idle, .feedback, .failed:
            await startFollowReadSession()
        case .recording:
            await finishFollowReadRecording()
        case .playingReference, .processing:
            break
        }
    }

    private func startFollowReadSession() async {
        followRead.retry()
        reader.stop()
        followRead.beginReferencePlayback(for: current)
        reader.onReadingFinished = {
            reader.onReadingFinished = nil
            followRead.referencePlaybackFinished()
            guard case .recording = followRead.phase else { return }
            Task { @MainActor in
                do {
                    try practiceRecorder.start()
                } catch {
                    followRead.fail(error.localizedDescription)
                }
            }
        }
        reader.toggleRead(current)
    }

    private func finishFollowReadRecording() async {
        followRead.beginProcessing()
        // 猎虫③ F2: capture the target BEFORE the cloud transcription await — the
        // user can switch sentences mid-recognition, and the late result must not
        // be scored (and banked into the drill store) against the new sentence.
        // The controller's phase guard handles the cancel race; this handles the
        // sentence swap.
        let target = current
        do {
            let recording = try await practiceRecorder.stopAndTranscribeKeepingAudio(language: "en")
            guard followRead.targetText == target.text else {
                practiceRecorder.cleanupAudio(at: recording.audioFileURL)
                return
            }
            let feedback = await FollowReadFeedbackBuilder.build(
                target: target.text,
                recognized: recording.text,
                audioFileURL: recording.audioFileURL,
                analysis: target)
            practiceRecorder.cleanupAudio(at: recording.audioFileURL)
            followRead.complete(with: feedback)
        } catch {
            // Same staleness check on the failure leg (fix-verifier residual): a
            // late transcription error from sentence A must not cancel sentence
            // B's in-flight recording or flash an error card on B's session.
            guard followRead.targetText == target.text else { return }
            practiceRecorder.cancel()
            followRead.fail(error.localizedDescription)
        }
    }

    private func retryFollowRead() {
        followRead.retry()
        Task { await startFollowReadSession() }
    }

    /// 303: the feedback card's exits write into the same drill store the
    /// 练习室 reads (SM-2 queue). Perfect reads bank nothing → returns false.
    private func bankFollowReadMistake(_ feedback: SpeechFeedback) -> Bool {
        guard let record = MistakeRecord.followRead(from: feedback),
              let store = try? SQLiteDrillStore.defaultStore() else { return false }
        do {
            try store.upsert(record)
            return true
        } catch {
            return false
        }
    }

    private func stopAllPlayback() {
        reader.onReadingFinished = nil
        reader.stop()
        practiceRecorder.cancel()
        if followReadActive { followRead.cancel() }
    }

    private func resetFollowRead() {
        reader.onReadingFinished = nil
        practiceRecorder.cancel()
        followRead.cancel()
    }
}