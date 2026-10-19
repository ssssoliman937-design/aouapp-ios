import SwiftUI

/// Welcome → Connect your university, same two steps as Android
/// (welcome_page.dart → login_page.dart, goldens 46 and 01).
struct AuthFlowView: View {
    @State private var connecting = false

    var body: some View {
        ZStack {
            if connecting {
                ConnectView(back: { connecting = false }).transition(.move(edge: .trailing))
            } else {
                WelcomeView(connect: { connecting = true }).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.26), value: connecting)
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let connect: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 120)
                BrandMark(size: 88)
                Text(model.t("app.name")).font(AppFont.body(26, weight: .bold)).foregroundStyle(palette.text).padding(.top, 18)
                Text(model.t("app.tagline")).font(AppFont.body(15)).foregroundStyle(palette.text2).padding(.top, 4)
                Button(action: connect) {
                    VStack(spacing: 2) {
                        Text(model.t("welcome.haveAccount")).font(AppFont.body(19, weight: .bold))
                        Text(model.t("welcome.haveAccountSub")).font(AppFont.body(13, weight: .semibold)).opacity(0.8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(palette.cta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.top, 22)
                HStack(spacing: 12) {
                    Rectangle().fill(palette.separatorStrong).frame(height: 1)
                    Text(model.t("welcome.or")).font(AppFont.body(13)).foregroundStyle(palette.text3)
                    Rectangle().fill(palette.separatorStrong).frame(height: 1)
                }
                .padding(.vertical, 22)
                Button(model.t("welcome.guest")) { Task { await model.signInDemo() } }
                    .font(AppFont.body(17)).foregroundStyle(palette.accent)
                Text(model.t("welcome.privacy")).padding(.top, 26)
                Text(model.t("app.disclaimer")).font(AppFont.body(12)).padding(.top, 8)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .font(AppFont.body(13))
            .foregroundStyle(palette.text2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .background(palette.bg.ignoresSafeArea())
    }
}

private struct ConnectView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let back: () -> Void
    @State private var studentId = ""
    @State private var sisPassword = ""
    @State private var lmsPassword = ""
    @State private var remember = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandMark(size: 64).padding(.top, 12)
                Text(model.t("login.title")).font(AppFont.body(26, weight: .bold)).foregroundStyle(palette.text).padding(.top, 18)
                Text(model.t("login.subtitle")).font(AppFont.body(15)).foregroundStyle(palette.text2)
                    .multilineTextAlignment(.center).padding(.top, 4).padding(.bottom, 22)

                Field(systemImage: "person.text.rectangle", placeholder: model.t("login.studentId"), text: $studentId, secure: false)
                    .keyboardType(.numberPad)
                SystemHint(tag: "SIS", text: model.t("login.sisHint"), fg: palette.accent, bg: palette.accentSoft)
                Field(systemImage: "lock", placeholder: model.t("login.sisPassword"), text: $sisPassword, secure: true)
                SystemHint(tag: "LMS", text: model.t("login.lmsHint"), fg: palette.ok, bg: palette.okSoft)
                Field(systemImage: "lock", placeholder: model.t("login.lmsPassword"), text: $lmsPassword, secure: true)

                Toggle(isOn: $remember) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t("login.remember")).font(AppFont.body(16, weight: .bold)).foregroundStyle(palette.text)
                        Text(model.t("login.rememberNote")).font(AppFont.body(12.5)).foregroundStyle(palette.text2)
                    }
                }
                .tint(palette.cta)
                .padding(.vertical, 18)

                if let error {
                    Text(error)
                        .font(AppFont.body(13, weight: .semibold)).foregroundStyle(palette.urgent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(palette.urgentSoft, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 12)
                }
                Button(busy ? model.t("login.signingIn") : model.t("login.submit"), action: submit)
                    .buttonStyle(PrimaryButtonStyle(palette: palette))
                    .disabled(busy)
                Text(model.t("app.disclaimer"))
                    .font(AppFont.body(12)).foregroundStyle(palette.text2)
                    .multilineTextAlignment(.center).padding(.top, 22)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 24)
        }
        .background(palette.bg.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button(action: back) { Image(systemName: "chevron.backward").font(.title3.weight(.semibold)) }
                .foregroundStyle(palette.text).padding(16)
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            error = await model.signIn(studentId: studentId, sisPassword: sisPassword, lmsPassword: lmsPassword)
            busy = false
            // Passwords are not kept once the sign-in calls are done.
            sisPassword = ""
            lmsPassword = ""
        }
    }
}

private struct Field: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let secure: Bool
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(palette.text2)
            Group {
                if secure && !revealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(AppFont.body(16))
            .foregroundStyle(palette.text)
            if secure {
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye" : "eye.slash")
                }
                .foregroundStyle(palette.text2)
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 54)
        .background(palette.fill2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.bottom, 10)
    }
}

private struct SystemHint: View {
    @Environment(\.palette) private var palette
    let tag: String
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: tag, fg: fg, bg: bg)
            Text(text).font(AppFont.body(13)).foregroundStyle(palette.text2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
