import SwiftUI

@main
struct AOUHubApp: App {
    @StateObject private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.layoutDirection, model.t.isRightToLeft ? .rightToLeft : .leftToRight)
                .environment(\.locale, Locale(identifier: model.language.rawValue))
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
            if phase == .active {
                Task { await model.checkForUpdates(userInitiated: false) }
            }
        }
    }
}
