import AOUHubCore
import SwiftUI

/// Settings in the V5 grouped-row style (Android More page rows).
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var lockMessage: String?

    var body: some View {
        Page {
            LargeHead(title: model.t("settings.title")) { EmptyView() }

            V5SectionLabel(text: model.t("settings.security")).padding(.bottom, 10)
            V5Group {
                V5Row(systemImage: "faceid", iconColor: palette.cta, title: model.t("settings.lock.faceID"),
                      subtitle: model.biometricStatus == .available ? model.t("settings.lock.hint") : model.t("settings.lock.unavailable")) {
                    Toggle("", isOn: Binding(
                        get: { model.lock.enabled },
                        set: { on in Task { lockMessage = await model.setLockEnabled(on) } }
                    ))
                    .labelsHidden().tint(palette.cta)
                    .disabled(model.biometricStatus != .available && !model.lock.enabled)
                }
                if let lockMessage {
                    Text(lockMessage).font(AppFont.body(13, weight: .semibold)).foregroundStyle(palette.urgent)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 14)
                }
            }

            V5SectionLabel(text: model.t("settings.updates")).padding(.bottom, 10)
            V5Group {
                Button { Task { await model.checkForUpdates(userInitiated: true) } } label: {
                    V5Row(systemImage: "arrow.triangle.2.circlepath", iconColor: palette.info,
                          title: model.t("settings.checkUpdates"), subtitle: updateLine) {
                        if model.updateStatus == .checking { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
            }

            V5SectionLabel(text: model.t("settings.language")).padding(.bottom, 10)
            V5Group {
                V5Row(systemImage: "globe", iconColor: palette.ok, title: model.t("settings.language")) {
                    Picker("", selection: $model.language) {
                        Text("العربية").tag(Localizer.Language.ar)
                        Text("English").tag(Localizer.Language.en)
                    }
                    .pickerStyle(.segmented).frame(width: 150)
                }
                Divider().overlay(palette.separator).padding(.leading, 64)
                Button { model.signOut() } label: {
                    V5Row(systemImage: "rectangle.portrait.and.arrow.right", iconColor: palette.urgent, title: model.t("settings.logout")) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var updateLine: String {
        switch model.updateStatus {
        case .checking: model.t("update.checking")
        case .upToDate: model.t("update.upToDate")
        case .failed: model.t("update.error")
        case .idle: model.t("settings.version", ["value": model.currentVersion.description])
        }
    }
}
