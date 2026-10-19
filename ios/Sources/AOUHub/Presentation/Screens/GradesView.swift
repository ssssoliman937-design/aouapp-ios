import AOUHubCore
import SwiftUI

/// V5 Grades: GPA hero with trend line + per-course mark bars (grades_page.dart, golden 07).
struct GradesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let snapshot: AcademicSnapshot

    var body: some View {
        let student = snapshot.student
        Page {
            LargeHead(title: model.t("grades.title")) {
                HStack(spacing: 10) {
                    roundIcon("scope")
                    roundIcon("doc.text")
                }
            }
            TermPill(term: student.term).padding(.top, 14)
            hero(student).padding(.top, 14)
            V5SectionLabel(text: model.t("grades.thisTerm")).padding(.bottom, 10)
            VStack(spacing: 12) {
                ForEach(snapshot.grades) { GradeCard(grade: $0) }
            }
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17)).foregroundStyle(palette.text)
            .frame(width: 40, height: 40).background(palette.fill2, in: Circle())
    }

    private func hero(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.t("grades.gpa")).font(AppFont.body(15)).opacity(0.85)
                Spacer()
                // Live sign-in has no term GPA (Android does not load one either); demo does.
                if let termGpa = student.termGpa {
                    Label {
                        Text("\(model.t("grades.termGpa")) \(termGpa.formatted(.number.precision(.fractionLength(2))))")
                    } icon: { Image(systemName: "chart.line.uptrend.xyaxis") }
                    .font(AppFont.body(13, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(student.gpa, format: .number.precision(.fractionLength(2))).font(AppFont.body(46, weight: .bold))
                Text("/ 4.00").font(AppFont.body(15, weight: .bold)).opacity(0.6)
            }
            .padding(.top, 8)
            if student.gpaHistory.count > 1 {
                Sparkline(values: student.gpaHistory).frame(height: 64).padding(.top, 10)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(palette.heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(red: 0, green: 0.18, blue: 0.35).opacity(0.5), radius: 22, y: 18)
    }
}

/// GPA trend: filled area + line + dots, last point emphasised.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                }
                .fill(.white.opacity(0.14))
                Path { p in p.addLines(pts) }.stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ForEach(pts.indices, id: \.self) { i in
                    Circle().fill(.white).frame(width: i == pts.count - 1 ? 9 : 6).position(pts[i])
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let min = lo - 0.1, span = (hi + 0.05) - min
        return values.enumerated().map { i, v in
            CGPoint(x: 4 + CGFloat(i) / CGFloat(values.count - 1) * (size.width - 8),
                    y: size.height - 8 - CGFloat((v - min) / span) * (size.height - 20))
        }
    }
}
