import AOUHubCore
import QuickLook
import SwiftUI

/// course_hub_page.dart (goldens 27-31): navy header with code, name and
/// credits / open tasks / current total, then Overview · Content · Assignments · Grades.
struct CourseHubView: View {
    enum Tab: String, CaseIterable { case overview, content, assignments, grades }
    enum ContentState { case idle, loading, ready, failed(String) }

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let course: Course
    let snapshot: AcademicSnapshot

    @State private var tab: Tab = .overview
    @State private var sections: [CourseSection] = []
    @State private var state: ContentState = .idle
    @State private var preview: URL?
    @State private var downloading: Int?

    private var grade: Grade? { snapshot.grades.first { $0.code == course.code } }
    private var courseItems: [TimelineItem] { snapshot.timeline.filter { $0.course == course.code } }

    /// LMS events for the course + assignments/quizzes found in its content.
    /// Timeline deadlines (already classified) + dated activities from the course page,
    /// classified the same way and de-duplicated against the calendar ("Quiz 2 closes" = "Quiz 2").
    private var tasks: [TimelineItem] {
        let events: [TimelineItem] = courseItems.filter { $0.type == .assignment || $0.type == .quiz }
        let seen: Set<String> = Set(events.map { DeadlineClassifier.activityKey($0.title) })
        let now = Date()
        var fromContent: [TimelineItem] = []
        for section in sections {
            for m in section.modules {
                let isTask = m.modname == "assign" || m.modname == "quiz"
                guard isTask, !seen.contains(DeadlineClassifier.activityKey(m.name)), let due = m.due else { continue }
                let verdict = DeadlineClassifier.classify(due: due, now: now, course: course, itemInstanceId: course.lmsCourseId)
                guard verdict.isCurrent else { continue }
                let type: EventType = m.modname == "assign" ? .assignment : .quiz
                fromContent.append(TimelineItem(id: "m-\(m.id)", title: m.name, type: type,
                                                start: due, end: nil, course: course.code, location: nil))
            }
        }
        return (events + fromContent).sorted { $0.start < $1.start }
    }

    var body: some View {
        let upcoming = tasks.filter { $0.start > Date() }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(openTasks: upcoming.count)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text(model.t("hub.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 14)
                Group {
                    switch tab {
                    case .overview: overview(upcoming: upcoming)
                    case .content: contentPane
                    case .assignments: assignmentsPane
                    case .grades:
                        if let grade { GradeCard(grade: grade).padding(.top, 14) } else { empty("—") }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 60)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task { await loadContent() }
        .quickLookPreview($preview)
    }

    // MARK: Header

    private func header(openTasks: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward").font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40).background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("Back")
            .padding(.bottom, 10)
            Text(course.code).font(AppFont.body(15, weight: .bold)).opacity(0.9)
            Text(course.name).font(AppFont.body(26, weight: .bold)).padding(.bottom, 14)
            HStack(spacing: 26) {
                stat(course.creditHours.map(String.init) ?? "—", model.t("hub.creditHours"))
                stat("\(openTasks)", model.t("hub.assignments"))
                stat(grade.map { $0.total.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", model.t("hub.currentTotal"))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 24)
        .background(LinearGradient(colors: palette.hero.reversed(), startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(AppFont.body(24, weight: .bold)).monospacedDigit()
            Text(label).font(AppFont.body(12.5)).opacity(0.8)
        }
    }

    // MARK: Panes

    @ViewBuilder
    private func overview(upcoming: [TimelineItem]) -> some View {
        let next = courseItems.first { $0.type == .lecture && $0.start > Date() }
        let exams = courseItems.filter { $0.type == .exam && $0.start > Date() }
        if let due = upcoming.first, case .left(let n, let unit) = TimeLeft(from: Date(), to: due.start) {
            Label(model.t("hub.deadlineIn", ["value": "\(n) \(model.t("today.unit.\(unit)"))"]), systemImage: "checklist")
                .font(AppFont.body(15, weight: .bold)).foregroundStyle(palette.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(palette.warnSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 14)
        }
        V5SectionLabel(text: model.t("hub.nextLecture")).padding(.bottom, 10)
        if let next { PriorityRow(item: next) } else { empty(model.t("hub.noUpcomingLecture")) }
        V5SectionLabel(text: model.t("hub.lecturer")).padding(.bottom, 10)
        V5Group {
            V5Row(systemImage: "person", iconColor: palette.text3, title: course.tutor ?? model.t("hub.instructorNotFound"),
                  subtitle: course.section.map { model.t("hub.section", ["value": $0]) }) { EmptyView() }
        }
        if !exams.isEmpty {
            V5SectionLabel(text: model.t("hub.exams")).padding(.bottom, 10)
            VStack(spacing: 10) { ForEach(exams) { PriorityRow(item: $0) } }
        }
    }

    @ViewBuilder
    private var contentPane: some View {
        if course.lmsCourseId == nil || !model.canLoadContent {
            empty(model.t("hub.lmsNotLinked"))
        } else {
            switch state {
            case .idle, .loading:
                ProgressView(model.t("hub.loading")).frame(maxWidth: .infinity).padding(.top, 30)
            case .failed(let error):
                VStack(spacing: 10) {
                    empty(model.t("hub.loadFailed", ["error": error]))
                    Button(model.t("common.retry")) { Task { await loadContent(force: true) } }
                }
            case .ready where sections.isEmpty:
                empty(model.t("hub.noContent"))
            case .ready:
                ForEach(sections) { section in
                    V5SectionLabel(text: section.name).padding(.bottom, 10)
                    V5Group {
                        ForEach(Array(section.modules.enumerated()), id: \.element.id) { i, module in
                            if i > 0 { Divider().overlay(palette.separator).padding(.leading, 64) }
                            moduleRow(module)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assignmentsPane: some View {
        if tasks.isEmpty {
            empty(model.t("hub.noAssignments"))
        } else {
            VStack(spacing: 10) { ForEach(tasks) { PriorityRow(item: $0) } }.padding(.top, 14)
        }
    }

    private func moduleRow(_ m: CourseModule) -> some View {
        let look: (icon: String, tone: String) = switch m.modname {
        case "resource", "page": ("doc.text", "accent")
        case "folder": ("folder", "accent")
        case "forum": ("bubble.left", "ok")
        case "assign": ("checklist", "warn")
        case "quiz": ("questionmark.circle", "info")
        case "url": ("link", "accent")
        default: ("doc", "text3")
        }
        var subtitle: String?
        if let due = m.due {
            subtitle = "\(model.t("hub.dueOn")) \(due.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
        } else if let size = m.primaryFile?.size {
            subtitle = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return Button { Task { await open(m) } } label: {
            V5Row(systemImage: look.icon, iconColor: palette.tone(look.tone), title: m.name, subtitle: subtitle) {
                if downloading == m.id {
                    ProgressView()
                } else if m.primaryFile != nil {
                    Image(systemName: "arrow.down.to.line").foregroundStyle(palette.text3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(m.primaryFile == nil && m.url == nil)
    }

    private func empty(_ text: String) -> some View {
        V5Group {
            Text(text).font(AppFont.body(14)).foregroundStyle(palette.text2)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(22)
        }
        .padding(.top, 10)
    }

    // MARK: Actions

    private func loadContent(force: Bool = false) async {
        guard course.lmsCourseId != nil, model.canLoadContent else { return }
        if case .ready = state, !force { return }
        state = .loading
        do {
            sections = try await model.contents(of: course)
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// A file opens in Quick Look from the app's private storage; anything else opens on the LMS.
    private func open(_ m: CourseModule) async {
        if let file = m.primaryFile {
            downloading = m.id
            defer { downloading = nil }
            if let url = try? await model.download(file) { preview = url }
        } else if let url = m.url {
            openURL(url)
        }
    }
}
