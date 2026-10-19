import Foundation

/// android/lib/domain/grade_math.dart: the AOU letter scale and the GPA arithmetic.
public enum GradeMath {
    public struct Band: Equatable, Sendable {
        public let letter: String
        public let floor: Double
        public let points: Double
    }

    public static let scale: [Band] = [
        Band(letter: "A", floor: 90, points: 4.0), Band(letter: "B+", floor: 85, points: 3.5),
        Band(letter: "B", floor: 80, points: 3.0), Band(letter: "C+", floor: 75, points: 2.5),
        Band(letter: "C", floor: 70, points: 2.0), Band(letter: "D+", floor: 65, points: 1.5),
        Band(letter: "D", floor: 60, points: 1.0), Band(letter: "F", floor: 0, points: 0.0),
    ]

    static func band(forTotal total: Double) -> Band {
        scale.first { total >= $0.floor } ?? scale[scale.count - 1]
    }

    /// A published letter, else the earned total once the final is in.
    public static func bandOf(_ g: Grade) -> Band? {
        let status = g.status.trimmingCharacters(in: .whitespaces).uppercased()
        if let published = scale.first(where: { $0.letter == status }) { return published }
        guard g.final != nil else { return nil }
        return band(forTotal: g.total)
    }

    /// Credit-weighted points; withheld and unknown rows are skipped.
    public static func gpaOf(_ grades: [Grade]) -> Double? {
        var points = 0.0, hours = 0.0
        for g in grades {
            guard let h = g.creditHours, h > 0, !g.withheld, let band = bandOf(g) else { continue }
            points += band.points * Double(h)
            hours += Double(h)
        }
        return hours == 0 ? nil : points / hours
    }
}

/// A Moodle course section and its activities (models.dart CourseSection / CourseModule).
public struct CourseSection: Identifiable, Equatable, Sendable {
    public var id: String { name + "\(modules.first?.id ?? 0)" }
    public let name: String
    public let modules: [CourseModule]
}

public struct CourseModule: Identifiable, Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let name: String
        public let url: URL
        public let size: Int?
    }

    public let id: Int
    public let name: String
    /// Moodle modname: resource, page, folder, forum, assign, quiz, url…
    public let modname: String
    public let url: URL?
    public let due: Date?
    public let files: [File]

    /// A downloadable document (opened in-app), as opposed to a Moodle page.
    public var primaryFile: File? { modname == "resource" ? files.first : nil }
}
