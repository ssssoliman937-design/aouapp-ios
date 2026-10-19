import Foundation

/// android/lib/domain/assignment_classifier.dart: ONE place that decides whether
/// an LMS deadline belongs to the current term, so a previous run's
/// "TMA Submission Link" never shows as overdue.
public enum DeadlineClass: Equatable, Sendable {
    case upcoming, overdue, archived, unknown

    public var isCurrent: Bool { self == .upcoming || self == .overdue }
}

public enum DeadlineClassifier {
    static let preStartGrace: TimeInterval = 14 * 86_400
    static let overdueWindow: TimeInterval = 45 * 86_400
    static let postEndGrace: TimeInterval = 30 * 86_400
    static let implausibleAfterEnd: TimeInterval = 90 * 86_400

    /// `course` is the registered course (its current Moodle run); nil = not registered this term.
    public static func classify(due: Date, now: Date, course: Course?, itemInstanceId: Int?) -> DeadlineClass {
        if let item = itemInstanceId, let current = course?.lmsCourseId, item != current { return .archived }
        guard let course else { return .unknown }
        guard let start = course.lmsStart else { return .unknown }
        if due < start.addingTimeInterval(-preStartGrace) { return .archived }
        if let end = course.lmsEnd {
            if due > end.addingTimeInterval(implausibleAfterEnd) { return .unknown }
            if now > end.addingTimeInterval(postEndGrace) { return .archived }
        }
        if due >= now { return .upcoming }
        return now.timeIntervalSince(due) <= overdueWindow ? .overdue : .archived
    }

    /// "Quiz 2 closes" / "TMA 1 is due" are Moodle's calendar names for the activity "Quiz 2" / "TMA 1".
    public static func activityKey(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: #"\s+(closes|opens|is due|due)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
