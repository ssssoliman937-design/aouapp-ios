import AOUHubCore
import SwiftUI

/// Login or the tab shell, with the Face ID cover and the update prompt on top.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(tokens: model.tokens, scheme: scheme)
        ZStack {
            switch model.session {
            case .signedOut:
                AuthFlowView()
            case .signedIn(let snapshot):
                MainTabView(snapshot: snapshot)
                    // Hidden from VoiceOver while the lock covers it.
                    .accessibilityHidden(model.showsLock)
            }
            if model.showsLock {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .environment(\.palette, palette)
        .font(AppFont.body())
        .tint(palette.accent)
        .animation(.easeOut(duration: 0.26), value: model.showsLock)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(AppFont.body(13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        model.notice = nil
                    }
            }
        }
        .animation(.easeOut(duration: 0.26), value: model.notice)
        .sheet(item: $model.pendingUpdate) { release in
            UpdatePromptView(release: release)
                .environment(\.palette, palette)
                .presentationDetents([.medium])
        }
        .task(id: model.showsLock) {
            // One automatic Face ID prompt whenever the cover appears.
            if model.showsLock { await model.unlock() }
        }
    }
}


private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette? = nil
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self]! }
        set { self[PaletteKey.self] = newValue }
    }
}
