import AOUHubCore
import SwiftUI

/// V5 Planner: upcoming items by day, same priority rows as Today.
struct PlannerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let snapshot: AcademicSnapshot

    var body: some View {
        let days = model.today.agenda(snapshot.timeline, now: Date())
        Page {
            LargeHead(title: model.t("planner.title")) { TermPill(term: snapshot.student.term) }
            if days.isEmpty {
                Text(model.t("planner.empty")).foregroundStyle(palette.text2).padding(.top, 20)
            }
            ForEach(days) { day in
                V5SectionLabel(text: day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .padding(.bottom, 10)
                VStack(spacing: 10) {
                    ForEach(day.items) { PriorityRow(item: $0) }
                }
            }
        }
    }
}
