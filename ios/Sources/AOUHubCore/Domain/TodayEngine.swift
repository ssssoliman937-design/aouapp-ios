import Foundation

/// What the Today screen leads with. Pure, so the same rules are tested
/// without a UI (and mirror the Android Today ordering).
public struct TodayEngine: Sendable {
    /// How far ahead a deadline starts to "need attention".
    public let attentionWindow: TimeInterval

    public init(attentionWindow: TimeInterval = 72 * 3600) {
        self.attentionWindow = attentionWindow
    }

    /// The next lecture or exam that has not started yet.
    public func upNext(_ items: [TimelineItem], now: Date) -> TimelineItem? {
        items
            .filter { ($0.type == .lecture || $0.type == .exam) && $0.start > now }
            .min { $0.start < $1.start }
    }

    /// Overdue tasks first, then tasks due inside the window, soonest first.
    public func needsAttention(_ items: [TimelineItem], now: Date) -> [TimelineItem] {
        items
            .filter { $0.type.isTask && $0.start <= now.addingTimeInterval(attentionWindow) }
            .sorted { lhs, rhs in
                let lo = lhs.isOverdue(at: now), ro = rhs.isOverdue(at: now)
                return lo != ro ? lo : lhs.start < rhs.start
            }
    }

    /// Upcoming items grouped by calendar day, for the planner.
    public func agenda(_ items: [TimelineItem], now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        let upcoming = items.filter { $0.start >= calendar.startOfDay(for: now) }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { day in
            AgendaDay(day: day, items: grouped[day]!.sorted { $0.start < $1.start })
        }
    }
}

/// Count buckets for the Arabic-aware pulse line (shared/l10n `today.pulse.*`),
/// same as Android's V5Strings.pulse.
public enum PluralCategory: String, Sendable {
    case zero, one, two, few, many

    public init(_ n: Int) {
        switch n {
        case 0: self = .zero
        case 1: self = .one
        case 2: self = .two
        case 3...10: self = .few
        default: self = .many
        }
    }
}

/// The when-box on a priority row and the hero countdown.
public enum TimeLeft: Equatable, Sendable {
    case overdue
    case left(Int, unit: String) // unit: "min" | "hour" | "day" (l10n `today.unit.*`)

    public init(from now: Date, to start: Date) {
        let seconds = start.timeIntervalSince(now)
        guard seconds >= 0 else { self = .overdue; return }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { self = .left(minutes, unit: "min"); return }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 48 { self = .left(hours, unit: "hour"); return }
        self = .left(Int((Double(hours) / 24).rounded()), unit: "day")
    }
}

extension TodayEngine {
    public func greetingKey(_ now: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        return hour < 12 ? "today.goodMorning" : hour < 17 ? "today.goodAfternoon" : "today.goodEvening"
    }

    public func lecturesLeftToday(_ items: [TimelineItem], now: Date, calendar: Calendar = .current) -> Int {
        items.filter { $0.type == .lecture && $0.start >= now && calendar.isDate($0.start, inSameDayAs: now) }.count
    }
}

public struct AgendaDay: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public let day: Date
    public let items: [TimelineItem]
}
