import AOUHubCore
import SwiftUI

/// V5 Courses: grouped rows with colored monogram tiles (courses_page.dart, golden 09).
struct CoursesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let snapshot: AcademicSnapshot
    let openCourse: (Course) -> Void

    var body: some View {
        Page {
            LargeHead(title: model.t("courses.title")) { TermPill(term: snapshot.student.term) }
                .padding(.bottom, 14)
            V5Group {
                ForEach(Array(snapshot.courses.enumerated()), id: \.element.id) { index, course in
                    if index > 0 { Divider().overlay(palette.separator).padding(.leading, 76) }
                    Button { openCourse(course) } label: { row(course) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ course: Course) -> some View {
        HStack(spacing: 14) {
            Text(course.monogram)
                .font(AppFont.body(15, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(palette.tone(course.tone), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).font(AppFont.body(16, weight: .bold)).foregroundStyle(palette.text)
                Text(course.creditHours.map { "\(course.code) · \(model.t("courses.ch", ["value": $0]))" } ?? course.code)
                    .font(AppFont.body(13)).foregroundStyle(palette.text2)
                if let tutor = course.tutor {
                    Text(tutor).font(AppFont.body(13)).foregroundStyle(palette.text2)
                }
                if course.onLms {
                    Pill(text: model.t("courses.lms"), fg: palette.accent, bg: palette.accentSoft).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(palette.text3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
