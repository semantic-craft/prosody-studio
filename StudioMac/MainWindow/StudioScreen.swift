import SwiftUI
import ResponsayCore
import AppKit

/// 练习室 (Studio, issue 071) — error-driven adaptive **English** drills.
/// Mistakes are extracted from your real coach history; the engine drills them
/// with SM-2 spacing + desirable difficulty (no fixed question bank, ADR-0006).
struct StudioScreen: View {
    @State private var controller: DrillSessionController?
    @State private var allMistakes: [MistakeRecord] = []
    /// In-memory extraction kept for the no-store fallback (305 fix C).
    @State private var extracted: [MistakeRecord] = []
    @State private var answer = ""
    @State private var loaded = false
    /// 305: drill seed is due-first; when nothing is due we fall back to the
    /// full mistake list and say so (加练), instead of pretending it was due.
    @State private var isExtraPractice = false
    /// 305: 到点复习 — the sentence-card SRS queue (ReviewStore.due/grade).
    @State private var reviewVM: ReviewQueueViewModel?
    /// 304: FSI Listen step — auto-read the correct answer after a wrong try.
    @AppStorage("studio.autoReadAnswer") private var autoReadAnswer = true

    private let store: DrillStore? = try? SQLiteDrillStore.defaultStore()
    /// 304: Listen step — same TTS controller the pronunciation screen uses.
    private let reader = ReadAloudController()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }.padding(22)
            }
        }
        .background(SettingsTheme.bg)
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("练习室").font(.system(size: 22, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
                Text("用你真实的英语错误来练 — 不背题库 · 间隔复习 · 难度随表现调整")
                    .font(.system(size: 12.5)).foregroundStyle(SettingsTheme.ink2)
            }
            Spacer(minLength: 12)
            // 304: FSI Listen step switch.
            Toggle("答错自动朗读", isOn: $autoReadAnswer)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(SettingsTheme.hair).frame(height: 1) }
    }

    // MARK: Content router

    @ViewBuilder private var content: some View {
        // 305: 到点复习 — sentence cards due today, above the drill flow.
        if let reviewVM, reviewVM.current != nil || reviewVM.isFinished {
            reviewSection(reviewVM)
        }
        if let controller {
            if controller.isFinished {
                summaryCard(controller)
            } else if let item = controller.current {
                progressStrip(controller)
                drillCard(item, controller)
            }
        } else if reviewVM?.current == nil, reviewVM?.isFinished != true {
            // Review-finished banner already covers the "all done" case.
            emptyState
        }
    }

    // MARK: 到点复习 (305)

    @ViewBuilder private func reviewSection(_ vm: ReviewQueueViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13)).foregroundStyle(SettingsTheme.green)
                Text("到点复习").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Spacer()
                if vm.current != nil {
                    Text("还剩 \(vm.remaining) 张").font(SettingsTheme.mono)
                        .foregroundStyle(SettingsTheme.ink3)
                }
            }
            if let card = vm.current {
                reviewCard(card, vm)
            } else if vm.isFinished {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal").foregroundStyle(SettingsTheme.green)
                    Text("今天的复习做完了 · 复习了 \(vm.reviewedCount) 张")
                        .font(.system(size: 13)).foregroundStyle(SettingsTheme.ink2)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).warmCardSurface()
    }

    private func reviewCard(_ card: ReviewCard, _ vm: ReviewQueueViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recall prompt: what you were trying to say.
            VStack(alignment: .leading, spacing: 4) {
                Text("当时你说：").font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink3)
                Text(card.sourceText).font(SettingsTheme.serif(15)).foregroundStyle(SettingsTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vm.isRevealed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.idiomatic).font(SettingsTheme.serif(16))
                            .foregroundStyle(SettingsTheme.green)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { reader.toggleRead(.followReadSeed(from: card.idiomatic)) } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                        .help("朗读这句")
                    }
                    ForEach(card.reasons.prefix(2), id: \.self) { reason in
                        Label(reason, systemImage: "checkmark")
                            .font(.system(size: 12)).foregroundStyle(SettingsTheme.ink2)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(SettingsTheme.card2))

                // Same 4-grade row as the iOS review surface.
                HStack(spacing: 8) {
                    gradeButton(.wrong, vm: vm)
                    gradeButton(.hesitant, vm: vm)
                    gradeButton(.good, vm: vm)
                    gradeButton(.easy, vm: vm)
                }
            } else {
                Button("开口说一遍，再看答案") { vm.reveal() }
                    .controlSize(.large).keyboardShortcut(.return, modifiers: [.shift])
            }
        }
    }

    private func gradeButton(_ grade: ReviewGrade, vm: ReviewQueueViewModel) -> some View {
        Button(grade.title) { vm.grade(grade) }
            .buttonStyle(.bordered)
            .tint(grade.rawValue >= ReviewGrade.good.rawValue ? SettingsTheme.green : SettingsTheme.ink3)
    }

    // MARK: Drill card

    private func drillCard(_ item: DrillItem, _ controller: DrillSessionController) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.question).font(SettingsTheme.serif(17)).foregroundStyle(SettingsTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // 304: FSI Listen step — hear the cue before answering.
                Button { reader.toggleRead(.followReadSeed(from: item.question)) } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .help("朗读题干")
            }
            if let hint = item.hint {
                Label(hint, systemImage: "lightbulb").font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.ink2)
            }

            if let feedback = controller.lastFeedback {
                feedbackPanel(feedback)
                HStack(spacing: 10) {
                    Button("下一题") { answer = ""; controller.advance() }
                        .controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    if !feedback.correctAnswer.isEmpty {
                        Button { reader.toggleRead(.followReadSeed(from: feedback.correctAnswer)) } label: {
                            Label("听正确说法", systemImage: "speaker.wave.2")
                        }
                        .controlSize(.large)
                    }
                }
            } else {
                TextField("写出更地道的说法…", text: $answer, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(SettingsTheme.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.fieldBorder, lineWidth: 1))
                Button("提交") {
                    let feedback = controller.submit(answer)
                    record(controller, for: item)
                    // 304: wrong answer → hear the idiomatic target once (FSI
                    // Listen), toggleable in the header.
                    if autoReadAnswer, feedback.grade != .correct,
                       !feedback.correctAnswer.isEmpty {
                        reader.toggleRead(.followReadSeed(from: feedback.correctAnswer))
                    }
                }
                .controlSize(.large).keyboardShortcut(.return, modifiers: [.command])
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).warmCardSurface()
    }

    private func feedbackPanel(_ feedback: DrillFeedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(color(feedback.severity)).frame(width: 8, height: 8)
                Text(feedback.grade == .correct ? "答对了" : "再看看正确说法")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(color(feedback.severity))
            }
            if !feedback.correctAnswer.isEmpty {
                Text(feedback.correctAnswer).font(SettingsTheme.serif(15)).foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
            }
            if !feedback.explanation.isEmpty {
                Text(feedback.explanation).font(.system(size: 12.5)).foregroundStyle(SettingsTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(SettingsTheme.card2))
    }

    // MARK: Progress + summary

    private func progressStrip(_ c: DrillSessionController) -> some View {
        HStack(spacing: 12) {
            Text("第 \(c.answered + 1) / \(c.total) 题").font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SettingsTheme.ink2)
            difficultyChip(c.difficulty)
            // 305: nothing due → this set is extra practice, say so.
            if isExtraPractice {
                Text("加练 · 暂无到期错题").font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(SettingsTheme.card2, in: Capsule())
                    .foregroundStyle(SettingsTheme.ink3)
            }
            Spacer()
            if c.answered > 0 {
                Text("正确率 \(Int(c.successRate * 100))%").font(SettingsTheme.mono).foregroundStyle(SettingsTheme.ink3)
            }
        }
    }

    private func summaryCard(_ c: DrillSessionController) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 30)).foregroundStyle(SettingsTheme.green)
            Text("练完啦").font(SettingsTheme.serif(20)).foregroundStyle(SettingsTheme.ink)
            Text("答对 \(c.correct) / \(c.answered) · 正确率 \(Int(c.successRate * 100))%")
                .font(.system(size: 13)).foregroundStyle(SettingsTheme.ink2)
            Button("再来一组") { startSession() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).warmCardSurface()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile").font(.system(size: 28)).foregroundStyle(SettingsTheme.ink3)
            Text("还没有英语错题，也没有到期的句子复习。多用语音教练 / 划词教练，系统会自动收集你的真实错误来练；复习到点了会出现在这里。")
                .font(.system(size: 13)).foregroundStyle(SettingsTheme.ink2)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Chips + shell

    private func difficultyChip(_ d: DrillDifficulty) -> some View {
        let label = d == .easy ? "简单" : (d == .medium ? "适中" : "进阶")
        return Text(label).font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(SettingsTheme.card2, in: Capsule()).foregroundStyle(SettingsTheme.ink2)
    }


    private func color(_ s: DrillFeedback.Severity) -> Color {
        s == .good ? SettingsTheme.green : SettingsTheme.wine
    }

    // MARK: Data

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // 305: sentence-card SRS queue (due today only).
        if let reviewStore = try? SQLiteReviewStore.defaultStore() {
            let vm = ReviewQueueViewModel(store: reviewStore)
            vm.load()
            reviewVM = vm
        }
        let captures = (try? Self.captureStore().recent(300)) ?? []
        extracted = captures.flatMap { EnglishMistakeExtractor().extract(from: $0) }
        for mistake in extracted { try? store?.upsert(mistake) }
        startSession()
    }

    /// 305: drills seed from `due()` so SM-2 scheduling is actually read —
    /// answered-correct mistakes stay away until due. With nothing due, the
    /// full list is offered as 加练 (labelled, not silently pretending). A
    /// missing store falls back to the in-memory extraction (pre-305 behavior).
    private func startSession() {
        guard let store else {
            allMistakes = extracted
            isExtraPractice = false
            controller = allMistakes.isEmpty ? nil : DrillSessionController(mistakes: allMistakes)
            answer = ""
            return
        }
        let due = (try? store.due(now: Date(), limit: 50)) ?? []
        if due.isEmpty {
            allMistakes = (try? store.all()) ?? []
            isExtraPractice = !allMistakes.isEmpty
        } else {
            allMistakes = due
            isExtraPractice = false
        }
        controller = allMistakes.isEmpty ? nil : DrillSessionController(mistakes: allMistakes)
        answer = ""
    }

    private func record(_ c: DrillSessionController, for item: DrillItem) {
        let correct = c.lastFeedback?.grade == .correct
        try? store?.recordResult(mistakeID: item.mistakeID, correct: correct, reviewedAt: Date())
    }

    private static func captureStore() -> CaptureStore {
        if let sqlite = try? SQLiteReviewStore.defaultStore() {
            return ReviewCaptureStore(reviewStore: sqlite)
        }
        return FileCaptureStore.defaultStore()
    }
}
