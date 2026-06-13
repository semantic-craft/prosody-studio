import SwiftUI

/// Parked surface (issue 352). The iOS "表达" flow ran on the retired Node backend
/// (removed in issue 353 / ADR-0029). It returns in M3, rebuilt on the app-direct BYOK
/// path the macOS app already uses. Until then this is a placeholder so the iOS target
/// keeps building without any backend dependency.
struct ExpressView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Theme.accent)
                Text("表达")
                    .font(.title2.weight(.semibold))
                Text("这个功能正在迁移到直连模式（BYOK），将在 iOS M3 版本回归。\n目前请在 macOS 上使用完整体验。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle("表达")
        }
    }
}

#Preview {
    ExpressView()
}
