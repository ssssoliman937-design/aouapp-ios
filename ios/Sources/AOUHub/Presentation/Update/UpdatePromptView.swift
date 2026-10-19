import AOUHubCore
import SwiftUI

/// Shown when the iOS repository has a newer release than this build.
struct UpdatePromptView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    let release: ReleaseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.t("update.available.title"), systemImage: "arrow.down.app")
                .font(AppFont.body(20, weight: .heavy))
                .foregroundStyle(palette.text)
            Text(model.t("update.available.body", [
                "latest": release.version.description,
                "current": model.currentVersion.description,
            ]))
            .foregroundStyle(palette.text2)
            if !release.notes.isEmpty {
                V5SectionLabel(text: model.t("update.notes"))
                ScrollView {
                    Text(release.notes)
                        .font(AppFont.body(13))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            Button(model.t("update.now")) {
                openURL(release.pageURL)
                model.pendingUpdate = nil
            }
            .buttonStyle(PrimaryButtonStyle(palette: palette))
            Button(model.t("update.later")) { model.snoozeUpdate() }
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(palette.elevated)
    }
}
