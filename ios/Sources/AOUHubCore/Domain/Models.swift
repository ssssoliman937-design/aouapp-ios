import Foundation

public enum EventType: String, Decodable, Sendable, CaseIterable {
    case lecture, assignment, quiz, exam, event

    /// Deadlines and exams can need attention; lectures and events never do.
    public var isTask: Bool { self == .assignment || self == .quiz || self == .exam }
}

public struct Student: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let firstName: String
    public let initials: String
    public let program: String
    public let track: String
    public let gpa: Double
    /// Not in the SIS sign-in payload; only the demo fixture has it.
    public let termGpa: Double?
    public let gpaHistory: [Double]
    public let completionPct: Int
    public let completedHours: Int
    public let registeredHours: Int
    public let totalHours: Int
    public let term: String
    public let unreadNotifications: Int
    public let syncedMinutesAgo: Int
}

public struct TimelineItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let type: EventType
    public let start: Date
    public let end: Date?
    public let course: String?
    public let location: String?
    /// Moodle course id the deadline came from (LMS events only), for DeadlineClassifier.
    public var lmsCourseId: Int? = nil

    public init(id: String, title: String, type: EventType, start: Date, end: Date?,
                course: String?, location: String?, lmsCourseId: Int? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.start = start
        self.end = end
        self.course = course
        self.location = location
        self.lmsCourseId = lmsCourseId
    }

    public func isOverdue(at now: Date) -> Bool { type.isTask && start < now }
}

public struct Course: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let creditHours: Int?
    public let onLms: Bool
    /// Tile color token name from shared/design/tokens.json (accent, brand, ok, info…).
    public let tone: String
    /// Moodle course id of the CURRENT run (pickCurrentInstance); nil = not on the LMS.
    public var lmsCourseId: Int? = nil
    /// That run's Moodle startdate / enddate, the window DeadlineClassifier judges in.
    public var lmsStart: Date? = nil
    public var lmsEnd: Date? = nil
    /// The student's own enrolled section and its lecturer(s), from SIS.
    public var section: String? = nil
    public var tutor: String? = nil

    /// "GT101" → "GT", as on the Android course tile.
    public var monogram: String { String(code.filter { !$0.isNumber }.prefix(2)) }
}

public struct Grade: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public let code: String
    public let creditHours: Int?
    public let status: String
    public let tma: Double?
    public let mid: Double?
    public let final: Double?

    /// models.dart Grade.pending
    public var isPending: Bool { status.lowercased().contains("pend") }

    /// SIS withholds results behind an unpaid balance: "--Cannot view: Unsettled Balance 11;".
    public var withheld: Bool { status.lowercased().contains("cannot view") }

    /// models.dart statusLabel: the withheld reason without the SIS marker characters.
    public var statusLabel: String {
        guard withheld else { return status }
        var s = status.replacingOccurrences(of: #"^[-\s]+|;+\s*$"#, with: "", options: .regularExpression)
        if let r = s.range(of: #"^Cannot view:\s*"#, options: [.regularExpression, .caseInsensitive]) { s.removeSubrange(r) }
        return s
    }

    /// Marks banked so far out of 100 (TMA 20 + mid 30 + final 50).
    public var total: Double { (tma ?? 0) + (mid ?? 0) + (final ?? 0) }
}

/// Everything the screens show, captured at one moment.
public struct AcademicSnapshot: Equatable, Sendable {
    public let student: Student
    public let timeline: [TimelineItem]
    public let courses: [Course]
    public let grades: [Grade]
}
