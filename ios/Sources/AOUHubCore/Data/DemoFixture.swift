import Foundation

/// shared/fixtures/demo.json: clearly fake data, times as hour offsets so the
/// demo is always "current".
public struct DemoFixture: Decodable, Sendable {
    struct StudentDTO: Decodable, Sendable {
        let id: Int
        let name, firstName, initials, program, track, term: String
        let gpa: Double
        let termGpa: Double?
        let gpaHistory: [Double]
        let completionPct, completedHours, registeredHours, totalHours: Int
        let unreadNotifications, syncedMinutesAgo: Int
    }

    struct TimelineDTO: Decodable, Sendable {
        let title: String
        let type: EventType
        let offsetHours: Double
        let durationHours: Double?
        let course: String?
        let location: String?
    }

    struct CourseDTO: Decodable, Sendable {
        let code, name, tone: String
        let creditHours: Int?
        let onLms: Bool
    }

    struct GradeDTO: Decodable, Sendable {
        let code, status: String
        let creditHours: Int
        let tma, mid, final: Double?
    }

    let student: StudentDTO
    let timeline: [TimelineDTO]
    let courses: [CourseDTO]
    let grades: [GradeDTO]

    public func snapshot(now: Date) -> AcademicSnapshot {
        let s = student
        return AcademicSnapshot(
            student: Student(
                id: s.id, name: s.name, firstName: s.firstName, initials: s.initials,
                program: s.program, track: s.track, gpa: s.gpa, termGpa: s.termGpa, gpaHistory: s.gpaHistory,
                completionPct: s.completionPct, completedHours: s.completedHours,
                registeredHours: s.registeredHours, totalHours: s.totalHours, term: s.term,
                unreadNotifications: s.unreadNotifications, syncedMinutesAgo: s.syncedMinutesAgo
            ),
            timeline: timeline.enumerated().map { index, t in
                let start = now.addingTimeInterval(t.offsetHours * 3600)
                return TimelineItem(
                    id: "demo-\(index)", title: t.title, type: t.type, start: start,
                    end: t.durationHours.map { start.addingTimeInterval($0 * 3600) },
                    course: t.course, location: t.location
                )
            },
            courses: courses.map { Course(code: $0.code, name: $0.name, creditHours: $0.creditHours, onLms: $0.onLms, tone: $0.tone) },
            grades: grades.map {
                Grade(code: $0.code, creditHours: $0.creditHours, status: $0.status, tma: $0.tma, mid: $0.mid, final: $0.final)
            }
        )
    }
}
