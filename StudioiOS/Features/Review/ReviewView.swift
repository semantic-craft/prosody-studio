import SwiftUI
import ResponsayCore

struct ReviewView: View {
    @State private var model = ReviewViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    summarySection
                    if let card = model.dueCards.first {
                        dueCard(card)
                    } else {
                        ContentUnavailableView(
                            "今天没有到期卡片",
                            systemImage: "checkmark.circle",
                            description: Text("最近的表达和跟读记录会留在这里。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                    recentSection
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .padding(Theme.Space.l)
            }
            .background(Theme.surface)
            .navigationTitle("复习")
            .task { model.load() }
            .refreshable { model.load() }
        }
    }

    private var summarySection: some View {
        HStack(spacing: Theme.Space.m) {
            metric("到期", value: model.dueCards.count, systemImage: "clock")
            metric("全部", value: model.totalCount, systemImage: "tray.full")
        }
    }

    private func metric(_ title: String, value: Int, systemImage: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .card(padding: Theme.Space.m)
    }

    private func dueCard(_ card: ReviewCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Label("当前卡片", systemImage: "rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(card.masteryStars)", systemImage: "star.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }

            Text(card.idiomatic)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.sourceText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !card.reasons.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(card.reasons.prefix(3), id: \.self) { reason in
                        Label(reason, systemImage: "checkmark")
                            .font(.callout)
                    }
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Space.s) {
                gradeButton(.wrong, systemImage: "arrow.uturn.backward")
                gradeButton(.hesitant, systemImage: "circle.lefthalf.filled")
                gradeButton(.good, systemImage: "checkmark.circle")
                gradeButton(.easy, systemImage: "star.circle")
            }
        }
        .card()
    }

    private func gradeButton(_ grade: ReviewGrade, systemImage: String) -> some View {
        Button {
            if let card = model.dueCards.first {
                model.grade(card, as: grade)
            }
        } label: {
            Label(grade.title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: Theme.controlRadius))
        .tint(grade.rawValue >= ReviewGrade.good.rawValue ? Theme.accent : .secondary)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("最近")
                .font(.headline)
            if model.recentCards.isEmpty {
                Text("还没有练习记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.recentCards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.idiomatic)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Text("间隔 \(card.intervalDays) 天 · 复习 \(card.repetitions) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if card.id != model.recentCards.last?.id {
                        Divider()
                    }
                }
            }
        }
        .card()
    }
}

#Preview {
    ReviewView()
}
