import Foundation

/// android/lib/domain/lecturer.dart LecturerNormalizer + Lecturer.displayName,
/// mirrored by simulator/src/live.js lecturerDisplay(). Repairs the SIS's free
/// text ("دكتورأحمد لطفي البابلي" → "دكتور أحمد لطفي البابلي"). Adds آنسة / سيد /
/// سيدة, which the live SIS also glues to names but Android does not know yet.
public enum LecturerNormalizer {
    enum Title: String {
        case professor, professorF, doctor, doctorF, ustadh, ustadha, engineer, engineerF, miss, mr, mrs

        var arabic: String {
            switch self {
            case .professor: return "أستاذ دكتور"
            case .professorF: return "أستاذة دكتورة"
            case .doctor: return "دكتور"
            case .doctorF: return "دكتورة"
            case .ustadh: return "أستاذ"
            case .ustadha: return "أستاذة"
            case .engineer: return "مهندس"
            case .engineerF: return "مهندسة"
            case .miss: return "آنسة"
            case .mr: return "سيد"
            case .mrs: return "سيدة"
            }
        }

        var english: String {
            switch self {
            case .professor, .professorF: return "Prof."
            case .doctor, .doctorF: return "Dr."
            case .ustadh, .mr: return "Mr."
            case .ustadha, .miss: return "Ms."
            case .mrs: return "Mrs."
            case .engineer, .engineerF: return "Eng."
            }
        }

        var feminine: Bool { [.doctorF, .ustadha, .professorF, .engineerF, .miss, .mrs].contains(self) }
    }

    /// Longest first, so "دكتورة" wins over "دكتور" and "سيدة" over "سيد".
    static let tokens: [(String, Title)] = [
        ("الدكتورة", .doctorF), ("الدكتور", .doctor), ("دكتورة", .doctorF), ("دكتور", .doctor),
        ("الأستاذة", .ustadha), ("الاستاذة", .ustadha), ("الأستاذ", .ustadh), ("الاستاذ", .ustadh),
        ("أستاذة", .ustadha), ("استاذة", .ustadha), ("أستاذ", .ustadh), ("استاذ", .ustadh),
        ("المهندسة", .engineerF), ("المهندس", .engineer), ("مهندسة", .engineerF), ("مهندس", .engineer),
        ("الآنسة", .miss), ("آنسة", .miss), ("انسة", .miss), ("السيدة", .mrs), ("السيد", .mr), ("سيدة", .mrs), ("سيد", .mr),
        ("أ.د.", .professor), ("أ.د", .professor), ("ا.د.", .professor), ("ا.د", .professor),
        ("د.", .doctor), ("د/", .doctor), ("أ.", .ustadh), ("أ/", .ustadh), ("م.", .engineer), ("م/", .engineer),
        ("prof.", .professor), ("prof", .professor), ("dr.", .doctor), ("dr", .doctor), ("eng.", .engineer), ("eng", .engineer),
        ("mrs.", .ustadha), ("mrs", .ustadha), ("ms.", .ustadha), ("ms", .ustadha), ("mr.", .ustadh), ("mr", .ustadh),
    ]

    /// Full words that may be glued to the following Arabic name. Never abbreviations.
    static let gluable: Set<String> = [
        "الدكتورة", "الدكتور", "دكتورة", "دكتور", "الأستاذة", "الاستاذة", "الأستاذ", "الاستاذ", "أستاذة", "استاذة", "أستاذ", "استاذ",
        "المهندسة", "المهندس", "مهندسة", "مهندس", "الآنسة", "آنسة", "انسة", "السيدة", "السيد", "سيدة", "سيد",
    ]

    /// Zero-width / bidi controls / soft hyphen / Arabic letter mark / BOM / tatweel.
    static let invisible: Set<UInt32> = {
        var s: Set<UInt32> = [0xAD, 0x61C, 0x640, 0x180E, 0xFEFF]
        for r in [0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069] { s.formUnion(r.map(UInt32.init)) }
        return s
    }()

    static func isArabicLetter(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x621...0x64A).contains($0.value) }
    }

    static func cleanText(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in raw.unicodeScalars where !invisible.contains(u.value) {
            scalars.append(CharacterSet.whitespacesAndNewlines.contains(u) ? " " : u)
        }
        var s = String(scalars)
        s = s.replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"\s+([.,،;:])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.،,/])(?=[^\s.،,/\d])"#, with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([أا])\.\s+د(\.?)"#, with: "$1.د$2", options: .regularExpression)
        return s.replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func leadingTitle(_ s: String) -> (Int, Title)? {
        let lower = s.lowercased()
        for (token, title) in tokens where lower.hasPrefix(token) {
            let rest = s.dropFirst(token.count)
            guard let after = rest.first else { return (token.count, title) }
            if after == " " || token.hasSuffix(".") || token.hasSuffix("/") { return (token.count, title) }
            if gluable.contains(token) && isArabicLetter(after) { return (token.count, title) } // "دكتورمحمد"
        }
        return nil
    }

    static func combine(_ ts: [Title]) -> Title? {
        guard let first = ts.first else { return nil }
        let set = Set(ts)
        let feminine = ts.contains { $0.feminine }
        let doctor = set.contains(.doctor) || set.contains(.doctorF)
        if set.contains(.professor) || set.contains(.professorF) || ((set.contains(.ustadh) || set.contains(.ustadha)) && doctor) {
            return feminine ? .professorF : .professor
        }
        if doctor { return feminine ? .doctorF : .doctor }
        return first
    }

    /// "<title> <name>", or the cleaned text when nothing was recognised.
    public static func display(_ raw: String, arabic: Bool) -> String {
        let cleaned = cleanText(raw)
        var rest = cleaned
        var titles: [Title] = []
        for _ in 0..<4 {
            guard !rest.isEmpty, let (length, title) = leadingTitle(rest) else { break }
            titles.append(title)
            rest = String(rest.dropFirst(length)).trimmingCharacters(in: .whitespaces)
        }
        rest = rest.replacingOccurrences(of: #"^[.,،/\-\s]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return cleaned }
        guard let title = combine(titles) else { return rest }
        let arabicName = rest.contains(where: isArabicLetter)
        return "\(arabicName || arabic ? title.arabic : title.english) \(rest)"
    }
}

extension LiveParsers {
    /// Moodle sends names HTML-encoded ("Revisions &amp; Prev Exams").
    public static func decodeEntities(_ raw: String) -> String {
        guard raw.contains("&") else { return raw }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        let pattern = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        var out = ""
        var last = raw.startIndex
        for m in pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let whole = Range(m.range, in: raw), let body = Range(m.range(at: 1), in: raw) else { continue }
            out += raw[last..<whole.lowerBound]
            let entity = String(raw[body])
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[entity.lowercased()]
            }
            out += replacement ?? String(raw[whole])
            last = whole.upperBound
        }
        return out + raw[last...]
    }
}
