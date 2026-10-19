import AOUHubCore
import SwiftUI

enum AppTab: String, CaseIterable {
    case today, courses, planner, grades, settings

    /// Tabs shown in the floating dock (Settings opens from the avatar, as Android's account sheet).
    static let dock: [AppTab] = [.today, .courses, .planner, .grades]

    var systemImage: String {
        switch self {
        case .today: "sun.horizon"
        case .courses: "text.book.closed"
        case .planner: "calendar"
        case .grades: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

/// V5 shell: page content under a floating capsule tab bar + round search
/// button (android/lib/ui/widgets/v5_shell.dart, goldens 48-50).
struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let snapshot: AcademicSnapshot
    @State private var tab: AppTab = .today
    /// The course hub is pushed over the shell, without the dock (as on Android).
    @State private var openCourse: Course?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .today: TodayView(snapshot: snapshot, openTab: { tab = $0 }, openCourse: { openCourse = $0 })
                case .courses: CoursesView(snapshot: snapshot, openCourse: { openCourse = $0 })
                case .planner: PlannerView(snapshot: snapshot)
                case .grades: GradesView(snapshot: snapshot)
                case .settings: SettingsView()
                }
            }
            dock
        }
        .fullScreenCover(item: $openCourse) { course in
            CourseHubView(course: course, snapshot: snapshot)
                .environmentObject(model)
                .environment(\.palette, palette)
                .environment(\.layoutDirection, model.t.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    private var dock: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.dock, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 1) {
                            Image(systemName: item.systemImage).font(.system(size: 20, weight: .medium))
                            Text(model.t("tab.\(item.rawValue)")).font(AppFont.body(12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(tab == item ? palette.accent : palette.text2)
                        .background(tab == item ? palette.accentSoft : .clear, in: Capsule())
                    }
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(palette.separator))
            Button {} label: {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(palette.separator))
            }
            .foregroundStyle(palette.text)
            .accessibilityLabel(model.t("tab.search"))
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}
