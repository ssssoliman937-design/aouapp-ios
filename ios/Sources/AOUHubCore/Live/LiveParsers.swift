import Foundation

// Line-for-line ports of the Android parsers (and of simulator/src/live.js):
//   android/lib/core/result.dart     SisEnvelope
//   android/lib/models/models.dart   normalizeCode, parseGradeDetails,
//                                    eventTypeFrom, _sisTimeOn, Grade.fromSis,
//                                    TimelineItem.fromSisSchedule / fromLmsEvent
//   android/lib/data/auth_repository.dart   _stdToken, logged user

typealias JSONObject = [String: Any]

enum JSONValue {
    static func string(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        return Double(string(v))
    }

    /// Whole number; SIS sends 2025.0 for a year and the stdtoken must say 2025.
    static func int(_ v: Any?) -> Int? { double(v).map { Int($0) } }
}

public struct SISEnvelope {
    public let isValid: Bool
    let data: Any?
    public let message: String?

    init(_ json: Any?) {
        guard let obj = json as? JSONObject else {
            isValid = true; data = json; message = nil
            return
        }
        let flag = obj["IsValid"] ?? obj["isValid"] ?? obj["Valid"]
        if let flag, !(flag is NSNull) {
            let s = JSONValue.string(flag).lowercased()
            isValid = s == "true" || s == "1"
        } else {
            isValid = true
        }
        data = obj.keys.contains("data") ? obj["data"] : obj
        let msg = JSONValue.string(obj["errorMessage"] ?? obj["ErrorMessage"] ?? obj["message"] ?? obj["Message"])
        message = msg.isEmpty ? nil : msg
    }
}

public enum LiveParsers {
    /// "2526-GT101 (01)" → "GT101".
    public static func normalizeCode(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if let m = s.range(of: #"^\s*\d{2,4}\s*-\s*"#, options: .regularExpression) {
            s = String(s[m.upperBound...])
        }
        if let m = s.range(of: #"\s*[-(]\s*\d{2,4}\s*\)?\s*$"#, options: .regularExpression) {
            s.removeSubrange(m)
        }
        return s.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// "TMA (0/20);Mid Term Assessment (19/30);Final Exam (33/50)".
    public static func parseGradeDetails(_ raw: String) -> (tma: Double?, mid: Double?, final: Double?) {
        var tma: Double?, mid: Double?, fin: Double?
        let pattern = try! NSRegularExpression(pattern: #"([\d.]+)\s*/\s*([\d.]+)"#)
        for entry in raw.split(separator: ";") where !entry.trimmingCharacters(in: .whitespaces).isEmpty {
            let text = String(entry)
            guard let m = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text),
                  let score = Double(text[r1]), let max = Double(text[r2]) else { continue }
            let name = text.lowercased()
            if max == 20 || name.contains("tma") { tma = score }
            else if max == 30 || name.contains("mid") { mid = score }
            else if max == 50 || name.contains("final") { fin = score }
        }
        return (tma, mid, fin)
    }

    /// EventType.other is shown as an event.
    public static func eventType(_ raw: String) -> EventType {
        let t = raw.lowercased()
        if t.contains("exam") { return .exam }
        if t.contains("lect") { return .lecture }
        if t.contains("assign") || t.contains("tma") { return .assignment }
        if t.contains("quiz") { return .quiz }
        return .event
    }

    /// "yyyy-MM-dd" + "HH:mm" (or "h:mm AM/PM", ص/م) in the device's time zone.
    public static func sisTime(day: String, time: String, calendar: Calendar = .current) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, !time.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let hm = time.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) else {
            return calendar.date(from: comps)
        }
        let nums = time[hm].split(separator: ":").compactMap { Int($0) }
        var hour = nums[0]
        let lower = time.lowercased()
        let pm = lower.contains("pm") || time.contains("م"), am = lower.contains("am") || time.contains("ص")
        if pm || am {
            if hour == 12 { hour = 0 }
            if pm { hour += 12 }
        }
        guard hour <= 23, nums[1] <= 59 else { return calendar.date(from: comps) }
        comps.hour = hour
        comps.minute = nums[1]
        return calendar.date(from: comps)
    }

    static func grade(_ j: JSONObject) -> Grade {
        let parsed = parseGradeDetails(JSONValue.string(j["Gradedetails"] ?? j["GradeDetails"]))
        return Grade(
            code: normalizeCode(JSONValue.string(j["Coursecode"] ?? j["CourseCode"] ?? j["Code"])),
            creditHours: JSONValue.int(j["Credits"] ?? j["CreditHours"]),
            status: JSONValue.string(j["Grade"]),
            tma: parsed.tma, mid: parsed.mid, final: parsed.final
        )
    }

    static func sisScheduleItem(_ j: JSONObject, arabic: Bool, index: Int) -> TimelineItem? {
        let code = JSONValue.string(j["Event_Type"])
        let type: EventType = code == "1" ? .lecture : code == "2" ? .exam : code == "3" ? .event : eventType(code)
        let course = normalizeCode(JSONValue.string(j["Course_Part_Code"]))
        let exam = JSONValue.string(j["Exam_Name"])
        let location = JSONValue.string(arabic ? (j["A_Location_Name"] ?? j["E_Location_Name"]) : (j["E_Location_Name"] ?? j["A_Location_Name"]))
        let day = JSONValue.string(j["date"])
        guard let start = sisTime(day: day, time: JSONValue.string(j["Start_Time"])) else { return nil }
        let title = !exam.isEmpty ? exam : !course.isEmpty ? course : (type == .lecture ? "Lecture" : "Event")
        return TimelineItem(
            id: "sis-\(index)", title: title, type: type, start: start,
            end: sisTime(day: day, time: JSONValue.string(j["End_Time"])),
            course: course.isEmpty ? nil : course, location: location.isEmpty ? nil : location
        )
    }

    static func lmsEvent(_ j: JSONObject, index: Int) -> TimelineItem? {
        guard let secs = JSONValue.int(j["timesort"] ?? j["timestart"]), secs > 0 else { return nil }
        let course = (j["course"] as? JSONObject).map { normalizeCode(JSONValue.string($0["shortname"])) }
        return TimelineItem(
            id: "lms-\(index)", title: decodeEntities(JSONValue.string(j["name"])),
            type: eventType(JSONValue.string(j["modulename"] ?? j["eventtype"])),
            start: Date(timeIntervalSince1970: TimeInterval(secs)), end: nil,
            course: (course?.isEmpty ?? true) ? nil : course, location: nil,
            lmsCourseId: JSONValue.int((j["course"] as? JSONObject)?["id"] ?? j["courseid"])
        )
    }

    /// Dart VM `String.hashCode` (Jenkins one-at-a-time over UTF-16, 30 bits),
    /// so tiles get exactly Android's colors. Verified against `dart` output in the tests.
    public static func dartStringHash(_ s: String) -> UInt32 {
        var h: UInt32 = 0
        for unit in s.utf16 {
            h = h &+ UInt32(unit)
            h = h &+ (h << 10)
            h ^= h >> 6
        }
        h = h &+ (h << 3)
        h ^= h >> 11
        h = h &+ (h << 15)
        h &= (1 << 30) - 1
        return h == 0 ? 1 : h
    }

    /// courses_page.dart: palette[code.hashCode % palette.length].
    public static func tone(for code: String) -> String {
        let palette = ["accent", "ok", "warn", "info", "urgent", "brand"]
        return palette[Int(dartStringHash(code) % UInt32(palette.count))]
    }

    /// "[MT131] Discrete Mathematics" → "Discrete Mathematics".
    public static func cleanCourseName(_ name: String, code: String) -> String {
        let s = decodeEntities(name).replacingOccurrences(of: #"^\s*\[[^\]]*\]\s*[-–:]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? code : s
    }

    /// models.dart RegisteredSection.fromSis: only rows with IsStatusEnrolled == true.
    static func lecturersByCode(_ rows: [JSONObject], arabic: Bool) -> [String: (section: String?, lecturers: [String])] {
        var out: [String: (section: String?, lecturers: [String])] = [:]
        for r in rows where (r["IsStatusEnrolled"] as? Bool) == true {
            let code = normalizeCode(JSONValue.string(r["CourseCode"]))
            let en = JSONValue.string(r["ForeignLecturerName"]), ar = JSONValue.string(r["ForeignLecturerNameAr"])
            let raw = arabic ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en)
            let name = raw.isEmpty ? "" : LecturerNormalizer.display(raw, arabic: arabic)
            let sectionName = JSONValue.string(r["ForeignSectionName"])
            var entry = out[code] ?? (section: sectionName.isEmpty ? nil : sectionName, lecturers: [])
            if !name.isEmpty, !entry.lecturers.contains(name) { entry.lecturers.append(name) }
            out[code] = entry
        }
        return out
    }

    struct LMSInstance {
        let id: Int?
        let name: String
        let start: Date?
        let end: Date?
    }

    /// assignment_classifier.dart pickCurrentInstance (TermPolicy: 30 days early open / post-end grace).
    static func pickCurrentInstance(_ instances: [LMSInstance], now: Date) -> LMSInstance? {
        guard instances.count > 1 else { return instances.first }
        let sorted = instances.sorted { a, b in
            if let sa = a.start, let sb = b.start, sa != sb { return sa > sb }
            if a.start != nil, b.start == nil { return true }
            if a.start == nil, b.start != nil { return false }
            return (a.id ?? 0) > (b.id ?? 0)
        }
        let grace: TimeInterval = 30 * 86_400
        func contains(_ c: LMSInstance) -> Bool {
            guard let s = c.start, s <= now.addingTimeInterval(grace) else { return false }
            guard let e = c.end else { return true }
            return now <= e.addingTimeInterval(grace)
        }
        return sorted.first(where: contains)
            ?? sorted.first { ($0.start ?? .distantFuture) <= now.addingTimeInterval(grace) }
            ?? sorted.first
    }

    /// models.dart CourseSection / CourseModule.fromLms (labels and empty sections dropped).
    static func sections(_ raw: Any?) -> [CourseSection] {
        ((raw as? [Any]) ?? []).compactMap { $0 as? JSONObject }.compactMap { s in
            let modules = ((s["modules"] as? [Any]) ?? []).compactMap { $0 as? JSONObject }
                .filter { JSONValue.string($0["modname"]) != "label" }
                .map { m -> CourseModule in
                    let files = ((m["contents"] as? [Any]) ?? []).compactMap { $0 as? JSONObject }
                        .filter { JSONValue.string($0["type"]) == "file" }
                        .compactMap { c -> CourseModule.File? in
                            guard let url = URL(string: JSONValue.string(c["fileurl"])) else { return nil }
                            return CourseModule.File(name: decodeEntities(JSONValue.string(c["filename"])), url: url, size: JSONValue.int(c["filesize"]))
                        }
                    return CourseModule(
                        id: JSONValue.int(m["id"]) ?? 0, name: decodeEntities(JSONValue.string(m["name"])),
                        modname: JSONValue.string(m["modname"]), url: URL(string: JSONValue.string(m["url"])),
                        due: dueFromDates(m["dates"]), files: files)
                }
            return modules.isEmpty ? nil : CourseSection(name: decodeEntities(JSONValue.string(s["name"])), modules: modules)
        }
    }

    /// CourseModule._dueFromDates: the "due"/"close" date of an activity.
    static func dueFromDates(_ raw: Any?) -> Date? {
        for d in ((raw as? [Any]) ?? []).compactMap({ $0 as? JSONObject }) {
            let label = JSONValue.string(d["label"]).lowercased()
            if label.contains("due") || label.contains("close"), let ts = JSONValue.int(d["timestamp"]), ts > 0 {
                return Date(timeIntervalSince1970: TimeInterval(ts))
            }
        }
        return nil
    }

    /// auth_repository.dart _stdToken: base64(json{StudentId, AcademicYear, AcademicSem}).
    static func stdToken(studentId: String, year: Int?, sem: Int?) -> String {
        func n(_ v: Int?) -> String { v.map(String.init) ?? "null" }
        let escaped = studentId.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let json = #"{"StudentId":"\#(escaped)","AcademicYear":\#(n(year)),"AcademicSem":\#(n(sem))}"#
        return Data(json.utf8).base64EncodedString()
    }
}
