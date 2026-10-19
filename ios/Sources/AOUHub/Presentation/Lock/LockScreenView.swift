import AOUHubCore
import SwiftUI

/// Full-screen Face ID cover. Error and fallback states mirror Android's
/// fingerprint lock screen; strings come from shared/l10n.
struct LockScreenView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            BrandMark(size: 88)
            Text(model.t("lock.title")).font(AppFont.body(24, weight: .bold)).foregroundStyle(palette.text)
            Text(model.t("lock.subtitle.faceID")).font(AppFont.body(14)).foregroundStyle(palette.text2)
            message
            Spacer()
            if !model.lockExhausted {
                Button {
                    Task { await model.unlock() }
                } label: {
                    Label(
                        model.lock.authenticating ? model.t("lock.authenticating") : model.t("lock.unlock.faceID"),
                        systemImage: "faceid"
                    )
                }
                .buttonStyle(PrimaryButtonStyle(palette: palette))
                .disabled(model.lock.authenticating)
            }
            if model.lockExhausted || model.lock.error != nil {
                Button(model.t("lock.fallback.logout"), role: .destructive) { model.signOut() }
                    .font(AppFont.body(14, weight: .semibold))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var message: some View {
        if let error = model.lock.error {
            let text = model.t("lock.error.\(error.rawValue)")
            let showLeft = error == .failed && !model.lockExhausted
            Text(showLeft ? "\(text) · \(model.t("lock.attemptsLeft", ["value": model.attemptsLeft]))" : text)
                .font(AppFont.body(13, weight: .semibold))
                .foregroundStyle(palette.urgent)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(palette.urgentSoft, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Color.clear.frame(height: 40)
        }
    }
}
