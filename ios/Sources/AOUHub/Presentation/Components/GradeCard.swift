import AOUHubCore
import SwiftUI

/// grades_page.dart _GradeCard: credits pill, status pill (withheld / pending /
/// letter), the withheld note, and TMA / mid-term / final bars.
struct GradeCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let grade: Grade

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(grade.code).font(AppFont.body(19, weight: .bold)).foregroundStyle(palette.text)
                Spacer()
                if let credits = grade.creditHours {
                    Pill(text: "\(credits) CH", fg: palette.text2, bg: palette.fill2)
                }
                status
            }
            .padding(.bottom, 8)
            if grade.withheld {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.urgent)
                    Text(model.t("grades.withheldNote")).foregroundStyle(palette.text2)
                }
                .font(AppFont.body(12.5))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.urgentSoft, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 4)
            }
            markRow(model.t("grades.tma"), grade.tma, of: 20, tone: "accent")
            markRow(model.t("grades.mid"), grade.mid, of: 30, tone: "info")
            markRow(model.t("grades.final"), grade.final, of: 50, tone: "urgent")
        }
        .padding(16)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        if grade.withheld {
            Pill(text: model.t("grades.withheld"), fg: palette.urgent, bg: palette.urgentSoft)
        } else if grade.isPending {
            Pill(text: model.t("grades.pending"), fg: palette.warn, bg: palette.warnSoft)
        } else {
            Pill(text: grade.statusLabel.isEmpty ? "—" : grade.statusLabel, fg: palette.ok, bg: palette.okSoft)
        }
    }

    private func markRow(_ label: String, _ value: Double?, of max: Double, tone: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).foregroundStyle(palette.text)
                Spacer()
                Text(value.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))/\(Int(max))" } ?? "—")
                    .bold().foregroundStyle(palette.tone(tone)).monospacedDigit()
            }
            .font(AppFont.body(15))
            GeometryReader { geo in
                Capsule().fill(palette.tone(tone + "Soft"))
                    .overlay(alignment: .leading) {
                        Capsule().fill(palette.tone(tone)).frame(width: geo.size.width * CGFloat((value ?? 0) / max))
                    }
            }
            .frame(height: 6)
        }
        .padding(.top, 10)
    }
}
