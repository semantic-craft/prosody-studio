import ResponsayCore
import SwiftUI

struct HomeView: View {
    @State private var model = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text("今天")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text("说一句,练到能自然出口。")
                                .font(.title2.weight(.semibold))
                            Text("从表达开始,再听、跟读、复盘。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            // TODO: route into a guided 15-minute session
                        } label: {
                            Label("开始练习", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()

                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack {
                            Text("最近")
                                .font(.headline)
                            Spacer()
                            Text("\(model.recentCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let latest = model.latestCard {
                            Text(latest.idiomatic)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                            Text("到期 \(model.dueCount) 张")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("还没有练习记录,去「表达」说一句试试。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .card()
                }
                .padding(Theme.Space.l)
            }
            .background(Theme.surface)
            .navigationTitle(AppBrand.displayName)
            .task { model.load() }
        }
    }
}

#Preview {
    HomeView()
}
