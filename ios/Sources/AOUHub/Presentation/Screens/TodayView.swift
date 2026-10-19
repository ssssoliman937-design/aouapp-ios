import AOUHubCore
import SwiftUI

/// V5 Today (android/lib/ui/today/v5_today_page.dart, goldens 48-50).
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let snapshot: AcademicSnapshot
    let openTab: (AppTab) -> Void
    let openCourse: (Course) -> Void

    var body: some View {
        let now = Date()
        let student = snapshot.student
        let next = model.today.upNext(snapshot.timeline, now: now)
        let attention = Array(model.today.needsAttention(snapshot.timeline, now: now).prefix(3))

        Page {
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(AppFont.body(14, weight: .semibold)).foregroundStyle(palette.text2)
            header(student, now: now)
            chips(student)
            Text(pulse(lectures: model.today.lecturesLeftToday(snapshot.timeline, now: now), needs: attention.count))
                .font(AppFont.body(16)).foregroundStyle(palette.text2)
                .padding(.bottom, 18)
            if let next {
                NowHero(item: next, course: snapshot.courses.first { $0.code == next.course }, openCourse: {
                    if let c = snapshot.courses.first(where: { $0.code == next.course }) { openCourse(c) } else { openTab(.courses) }
                })
            }
            SectionHead(kicker: model.t("today.attentionKicker"), title: model.t("today.attention"), seeAll: { openTab(.planner) })
            VStack(spacing: 10) {
                if attention.isEmpty {
                    V5Group {
                        VStack(spacing: 4) {
                            Text(model.t("today.empty")).font(AppFont.body(16, weight: .bold))
                            Text(model.t("today.emptyBody")).foregroundStyle(palette.text2)
                        }
                        .padding(28)
                    }
                }
                ForEach(attention) { item in
                    Button { openTab(.planner) } label: { PriorityRow(item: item) }.buttonStyle(.plain)
                }
            }
            SectionHead(kicker: model.t("today.standingKicker"), title: model.t("today.standing"))
            Button { openTab(.grades) } label: { standing(student) }.buttonStyle(.plain)
        }
    }

    private func header(_ student: Student, now: Date) -> some View {
        HStack(spacing: 8) {
            Text("\(model.t(model.today.greetingKey(now)))، \(student.firstName)")
                .font(AppFont.body(30, weight: .bold)).foregroundStyle(palette.text)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill").font(.system(size: 22)).foregroundStyle(palette.text2)
                    .frame(width: 40, height: 40)
                if student.unreadNotifications > 0 {
                    Text("\(student.unreadNotifications)")
                        .font(AppFont.body(11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
                        .background(palette.urgent, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            Button { openTab(.settings) } label: {
                Text(student.initials)
                    .font(AppFont.body(15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: palette.hero, startPoint: .top, endPoint: .bottom), in: Circle())
                    .overlay(Circle().stroke(palette.accentSoft, lineWidth: 3))
            }
            .accessibilityLabel(model.t("tab.settings"))
        }
    }

    private func chips(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AOUMarkShape().fill(palette.brandInk, style: FillStyle(eoFill: true)).frame(width: 12, height: 18)
                Text(model.t("university.name")).font(AppFont.body(14, weight: .bold)).foregroundStyle(palette.brandInk)
            }
            .chipStyle(palette)
            HStack(spacing: 8) {
                Circle().fill(palette.ok).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(palette.okSoft, lineWidth: 3))
                Text("\(model.t("today.synced")) · \(student.syncedMinutesAgo < 1 ? model.t("today.justNow") : model.t("today.agoMinutes", ["value": student.syncedMinutesAgo]))")
                    .font(AppFont.body(14, weight: .semibold)).foregroundStyle(palette.text2)
            }
            .chipStyle(palette)
        }
        .padding(.vertical, 14)
    }

    private func pulse(lectures: Int, needs: Int) -> String {
        model.t("today.pulse.sessions.\(PluralCategory(lectures).rawValue)", ["n": lectures])
            + model.t("today.pulse.needs.\(PluralCategory(needs).rawValue)", ["n": needs])
    }

    private func standing(_ student: Student) -> some View {
        V5Group {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text(student.gpa, format: .number.precision(.fractionLength(2)))
                        .font(AppFont.body(36, weight: .bold)).foregroundStyle(palette.text)
                    Text(model.t("today.gpa")).font(AppFont.body(13)).foregroundStyle(palette.text2)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text(model.t("today.completed")).foregroundStyle(palette.text2)
                        Spacer()
                        Text(student.totalHours > 0 ? "\(student.completedHours) / \(student.totalHours)" : "\(student.completedHours)").bold()
                    }
                    ProgressView(value: Double(student.completedHours), total: Double(max(student.totalHours, student.completedHours, 1)))
                        .tint(palette.accent)
                    if let termGpa = student.termGpa {
                        HStack {
                            Text(model.t("today.termGpa")).foregroundStyle(palette.text2)
                            Spacer()
                            Text(termGpa, format: .number.precision(.fractionLength(2))).bold()
                        }
                    }
                }
                .font(AppFont.body(13))
                .foregroundStyle(palette.text)
            }
            .padding(16)
        }
    }
}

/// The navy "Up next" hero with countdown and "Open course".
private struct NowHero: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let item: TimelineItem
    let course: Course?
    let openCourse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.36, green: 0.57, blue: 0.84)).frame(width: 8, height: 8)
                    Text(model.t("today.upNext")).font(AppFont.body(14, weight: .semibold)).opacity(0.9)
                }
                Spacer()
                if let code = item.course {
                    Text(code).font(AppFont.body(13, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16)))
                }
            }
            Text(course?.name ?? item.title).font(AppFont.body(24, weight: .bold)).padding(.top, 10)
            if let location = item.location {
                Label("\(model.t("today.room")) \(location)", systemImage: "mappin.and.ellipse")
                    .font(AppFont.body(14)).opacity(0.85)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if case .left(let n, let unit) = TimeLeft(from: Date(), to: item.start) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(n)").font(AppFont.body(46, weight: .bold)).monospacedDigit()
                            Text(model.t("today.unit.\(unit)")).font(AppFont.body(16, weight: .bold)).opacity(0.85)
                        }
                    }
                    Text("\(model.t("today.startsIn")) · \(timeRange)").font(AppFont.body(13)).opacity(0.8)
                }
                Spacer()
                Button(action: openCourse) {
                    Label(model.t("today.openCourse"), systemImage: "text.book.closed")
                        .font(AppFont.body(15, weight: .bold))
                        .foregroundStyle(Color(red: 0.016, green: 0.09, blue: 0.18))
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(.white, in: Capsule())
                }
            }
            .padding(.top, 18)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(palette.heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(red: 0, green: 0.18, blue: 0.35).opacity(0.5), radius: 22, y: 18)
    }

    private var timeRange: String {
        let f = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB"))
        return [item.start, item.end].compactMap { $0?.formatted(f) }.joined(separator: " – ")
    }
}

private extension View {
    func chipStyle(_ palette: Palette) -> some View {
        padding(.horizontal, 14).frame(height: 32)
            .background(palette.elevated, in: Capsule())
            .overlay(Capsule().stroke(palette.separator))
    }
}
