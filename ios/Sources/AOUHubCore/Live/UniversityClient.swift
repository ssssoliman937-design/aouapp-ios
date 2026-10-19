import Foundation

/// Signs into SIS and LMS exactly as android/lib/data/auth_repository.dart does,
/// then loads the current term. Mirrored by simulator/src/live.js signInLive().
///
/// - SIS: POST /api/Student/GetStudentByCredentials; valid = IsValid AND a
///   non-blank Id. The `_spaoutkn` cookie from Set-Cookie is the real
///   authorizer; every later call also sends `stdtoken` (base64 student
///   context) and `Authorization` (the login Token, no "Bearer").
/// - LMS: POST /login/token.php (service moodle_mobile_app) → web-service token.
/// - The two systems use separate passwords and succeed or fail independently.
/// - Passwords are only used for those two calls and never stored.
public struct UniversityClient: Sendable {
    let university: SharedAppConfig.University
    let transport: HTTPTransport

    public init(university: SharedAppConfig.University, transport: HTTPTransport) {
        self.university = university
        self.transport = transport
    }

    struct SISSession {
        let cookie: String?
        let stdToken: String
        let authorization: String?
        let user: JSONObject
    }

    // MARK: SIS

    func sisLogin(studentId: String, password: String) async -> Result<SISSession, LiveError> {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["Username": studentId, "Password": password])
            let res = try await transport.send(HTTPRequest(
                method: "POST", url: university.sisBase.appendingPathComponent("api/Student/GetStudentByCredentials"),
                headers: ["Content-Type": "application/json"], body: body))
            let env = SISEnvelope(res.json)
            guard res.status == 200, env.isValid, let user = env.data as? JSONObject,
                  !JSONValue.string(user["Id"]).isEmpty else {
                let reason = env.message ?? JSONValue.string((res.json as? JSONObject)?["Error"])
                return .failure(.rejected(reason.isEmpty ? (res.status == 200 ? "Wrong SIS password or student ID" : "HTTP \(res.status)") : reason))
            }
            let cookie = res.headers["set-cookie"].flatMap { header in
                header.range(of: #"_spaoutkn=[^;,]+"#, options: .regularExpression).map { String(header[$0]) }
            }
            let token = JSONValue.string(user["Token"])
            return .success(SISSession(
                cookie: cookie,
                stdToken: LiveParsers.stdToken(studentId: JSONValue.string(user["Id"]),
                                               year: JSONValue.int(user["AcademicYear"]), sem: JSONValue.int(user["AcademicSem"])),
                authorization: token.isEmpty ? nil : token,
                user: user))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    func sisGet(_ path: String, query: [String: String], session: SISSession) async throws -> Any? {
        var comps = URLComponents(url: university.sisBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var headers = ["Content-Type": "application/json", "stdtoken": session.stdToken]
        if let a = session.authorization { headers["Authorization"] = a }
        if let c = session.cookie { headers["cookie"] = c }
        let res = try await transport.send(HTTPRequest(url: comps.url!, headers: headers))
        return res.status == 200 ? SISEnvelope(res.json).data : nil
    }

    // MARK: LMS

    func lmsToken(studentId: String, password: String) async -> Result<String, LiveError> {
        do {
            let res = try await transport.send(HTTPRequest(
                method: "POST", url: university.lmsBase.appendingPathComponent("login/token.php"),
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: FormBody.encode([("username", studentId), ("password", password), ("service", university.lmsService)])))
            let obj = res.json as? JSONObject
            let token = JSONValue.string(obj?["token"])
            if !token.isEmpty { return .success(token) }
            let reason = JSONValue.string(obj?["error"] ?? obj?["errorcode"])
            return .failure(.rejected(reason.isEmpty ? "LMS token request failed" : reason))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    func lmsCall(_ token: String, _ function: String, _ args: [(String, String)] = []) async throws -> Any? {
        let res = try await transport.send(HTTPRequest(
            method: "POST", url: university.lmsBase.appendingPathComponent("webservice/rest/server.php"),
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: FormBody.encode([("wstoken", token), ("wsfunction", function), ("moodlewsrestformat", "json")] + args)))
        if let obj = res.json as? JSONObject, obj["exception"] != nil {
            throw LiveError.rejected(JSONValue.string(obj["message"] ?? obj["errorcode"]))
        }
        return res.json
    }

    // MARK: Sign-in + current term

    public func signIn(studentId: String, sisPassword: String, lmsPassword: String,
                       arabic: Bool, now: Date = Date()) async -> SignInOutcome {
        let sis: Result<SISSession, LiveError>
        if sisPassword.isEmpty {
            sis = .failure(.rejected("—"))
        } else {
            sis = await sisLogin(studentId: studentId, password: sisPassword)
        }
        let lms: Result<String, LiveError>
        if lmsPassword.isEmpty {
            lms = .failure(.rejected("—"))
        } else {
            lms = await lmsToken(studentId: studentId, password: lmsPassword)
        }

        var outcome = SignInOutcome(snapshot: nil, sisError: sis.errorText, lmsError: lms.errorText)
        outcome.lmsToken = lms.value
        let session = sis.value
        let token = lms.value
        if session != nil || token != nil {
            outcome.snapshot = await snapshot(sis: session, lmsToken: token, arabic: arabic, now: now)
        }
        return outcome
    }

    /// Each source fails on its own without blanking the others (as Android's unified repository).
    func snapshot(sis: SISSession?, lmsToken: String?, arabic: Bool, now: Date) async -> AcademicSnapshot {
        var term: Term?
        var grades: [Grade] = []
        var history: [(term: Term, gpa: Double)] = []
        var sisTimeline: [TimelineItem] = []
        var lecturers: [String: (section: String?, lecturers: [String])] = [:]
        if let sis {
            let sessions = (try? await sisGet("api/AcademicSession/GetStudentAcademicSessions", query: [:], session: sis)) as? [Any] ?? []
            let (terms, current) = Self.terms(sessions.compactMap { $0 as? JSONObject }, user: sis.user, arabic: arabic)
            term = current
            if let current {
                let scheduleRows = try? await sisGet("api/StudentSchedule/GetStudentSchedules", query: ["sessionId": current.id], session: sis)
                sisTimeline = ((scheduleRows as? [Any]) ?? []).enumerated().compactMap { i, row in
                    (row as? JSONObject).flatMap { LiveParsers.sisScheduleItem($0, arabic: arabic, index: i) }
                }
                var sectionQuery: [String: String] = [:]
                if let y = JSONValue.int(sis.user["AcademicYear"]) { sectionQuery["AcademicYear"] = "\(y)" }
                if let s = JSONValue.int(sis.user["AcademicSem"]) { sectionQuery["AcademicSem"] = "\(s)" }
                let sectionRows = try? await sisGet("api/StudentSection/GetStudentEnrolledSectionsByStudentID", query: sectionQuery, session: sis)
                lecturers = LiveParsers.lecturersByCode(((sectionRows as? [Any]) ?? []).compactMap { $0 as? JSONObject }, arabic: arabic)
                // providers.dart transcriptProvider: every term's grades → GradeMath.gpaOf, oldest first.
                for t in terms {
                    let rows = try? await sisGet("api/ViewStudentDetailedGrade/GetStudentDetailedGrades", query: ["AcademicSessionId": t.id], session: sis)
                    let g = ((rows as? [Any]) ?? []).compactMap { $0 as? JSONObject }.map(LiveParsers.grade).filter { !$0.code.isEmpty }
                    if t.id == current.id { grades = g }
                    if let gpa = GradeMath.gpaOf(g) { history.append((t, gpa)) }
                }
                history.sort { ($0.term.year ?? 0, $0.term.sem ?? 0) < ($1.term.year ?? 0, $1.term.sem ?? 0) }
            }
        }

        var lmsCourses: [JSONObject] = []
        var lmsEvents: [TimelineItem] = []
        if let lmsToken {
            let info = (try? await lmsCall(lmsToken, "core_webservice_get_site_info")) as? JSONObject
            if let uid = JSONValue.int(info?["userid"]) {
                lmsCourses = ((try? await lmsCall(lmsToken, "core_enrol_get_users_courses", [("userid", "\(uid)")])) as? [Any] ?? [])
                    .compactMap { $0 as? JSONObject }
            }
            let events = try? await lmsCall(lmsToken, "core_calendar_get_action_events_by_timesort",
                                            [("timesortfrom", "\(Int(now.timeIntervalSince1970))")])
            let list = ((events as? JSONObject)?["events"] as? [Any]) ?? (events as? [Any]) ?? []
            lmsEvents = list.enumerated().compactMap { i, e in (e as? JSONObject).flatMap { LiveParsers.lmsEvent($0, index: i) } }
        }

        return Self.assemble(user: sis?.user, term: term?.label, grades: grades, gpaHistory: history.map(\.gpa),
                             sisTimeline: sisTimeline, lmsCourses: lmsCourses, lmsEvents: lmsEvents,
                             lecturers: lecturers, arabic: arabic, now: now)
    }

    struct Term: Equatable {
        let id: String
        let label: String
        let year: Int?
        let sem: Int?
    }

    /// models.dart Term.fromSis for every session; repositories.dart marks the user's year/sem as current.
    static func terms(_ rows: [JSONObject], user: JSONObject, arabic: Bool) -> (all: [Term], current: Term?) {
        let all = rows.compactMap { row -> Term? in
            let en = JSONValue.string(row["AcademicSessionNameDetailed"]), ar = JSONValue.string(row["AcademicSessionNameArabicDetailed"])
            var label = arabic ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en)
            if label.isEmpty { label = "\(JSONValue.string(row["AcademicYear"])) / \(JSONValue.string(row["AcademicSem"]))" }
            let id = JSONValue.string(row["Id"] ?? row["AcademicSessionId"] ?? row["SessionId"])
            return id.isEmpty ? nil : Term(id: id, label: label, year: JSONValue.int(row["AcademicYear"]), sem: JSONValue.int(row["AcademicSem"]))
        }
        let year = JSONValue.int(user["AcademicYear"]), sem = JSONValue.int(user["AcademicSem"])
        return (all, all.first { $0.year == year && $0.sem == sem } ?? all.first)
    }

    /// repositories.dart unifiedCourses: this term's SIS registration is the list; the LMS
    /// only adds the name + content id of the CURRENT run; LMS-only enrolments are dropped.
    /// Without SIS data, the LMS's current courses stand in.
    static func unifiedCourses(grades: [Grade], lmsCourses: [JSONObject],
                               lecturers: [String: (section: String?, lecturers: [String])], now: Date) -> [Course] {
        var instances: [String: [LiveParsers.LMSInstance]] = [:]
        for c in lmsCourses {
            let code = LiveParsers.normalizeCode(JSONValue.string(c["shortname"]))
            guard !code.isEmpty else { continue }
            func date(_ v: Any?) -> Date? { JSONValue.int(v).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil } }
            instances[code, default: []].append(.init(id: JSONValue.int(c["id"]), name: JSONValue.string(c["fullname"]),
                                                      start: date(c["startdate"]), end: date(c["enddate"])))
        }
        let registered: [(code: String, credits: Int?)] = grades.isEmpty
            ? instances.keys.map { ($0, nil) }
            : grades.map { ($0.code, $0.creditHours) }
        return registered.compactMap { code, credits -> Course? in
            let lms = LiveParsers.pickCurrentInstance(instances[code] ?? [], now: now)
            if grades.isEmpty && lms == nil { return nil }
            let sec = lecturers[code]
            return Course(code: code, name: lms.map { LiveParsers.cleanCourseName($0.name, code: code) } ?? code,
                          creditHours: credits, onLms: lms != nil, tone: LiveParsers.tone(for: code),
                          lmsCourseId: lms?.id, lmsStart: lms?.start, lmsEnd: lms?.end, section: sec?.section,
                          tutor: (sec?.lecturers.isEmpty ?? true) ? nil : sec?.lecturers.joined(separator: " · "))
        }
        .sorted { $0.code < $1.code }
    }

    static func assemble(user: JSONObject?, term: String?, grades: [Grade], gpaHistory: [Double], sisTimeline: [TimelineItem],
                         lmsCourses: [JSONObject], lmsEvents: [TimelineItem],
                         lecturers: [String: (section: String?, lecturers: [String])], arabic: Bool, now: Date) -> AcademicSnapshot {
        let en = JSONValue.string(user?["StudentEnglishName"]), ar = JSONValue.string(user?["StudentArabicName"])
        let display = arabic ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en)
        let initialsSource = (en.isEmpty ? ar : en).split(separator: " ").prefix(2)
        let completed = JSONValue.int(user?["StudentCreditsCompleted"]) ?? 0
        let total = JSONValue.int(user?["StudentPlanCredits"]) ?? 0

        let student = Student(
            id: JSONValue.int(user?["Id"]) ?? 0,
            name: display.isEmpty ? "—" : display,
            firstName: String(display.split(separator: " ").first ?? "—"),
            initials: initialsSource.isEmpty ? "?" : initialsSource.map { String($0.prefix(1)) }.joined().uppercased(),
            program: JSONValue.string(arabic ? user?["ProgramNameArabic"] : user?["ProgramNameEnglish"]),
            track: JSONValue.string(user?["TrackName"]),
            gpa: JSONValue.double(user?["GPA"]) ?? 0,
            termGpa: GradeMath.gpaOf(grades), gpaHistory: gpaHistory,
            completionPct: total > 0 ? Int((Double(completed) / Double(total) * 100).rounded()) : 0,
            completedHours: completed, registeredHours: 0, totalHours: total,
            term: term ?? "", unreadNotifications: 0, syncedMinutesAgo: 0)

        let courses = unifiedCourses(grades: grades, lmsCourses: lmsCourses, lecturers: lecturers, now: now)
        return AcademicSnapshot(student: student,
                                timeline: currentTimeline(sis: sisTimeline, lms: lmsEvents, courses: courses, now: now),
                                courses: courses, grades: grades)
    }

    /// SIS schedule (lecture titles read as the course name, not a bare code) + only
    /// the LMS deadlines DeadlineClassifier calls current.
    static func currentTimeline(sis: [TimelineItem], lms: [TimelineItem], courses: [Course], now: Date) -> [TimelineItem] {
        let byCode = Dictionary(courses.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let schedule = sis.map { item -> TimelineItem in
            guard let code = item.course, item.title == code, let name = byCode[code]?.name, name != code else { return item }
            return TimelineItem(id: item.id, title: name, type: item.type, start: item.start, end: item.end,
                                course: item.course, location: item.location)
        }
        let deadlines = lms.filter { e in
            DeadlineClassifier.classify(due: e.start, now: now, course: e.course.flatMap { byCode[$0] },
                                        itemInstanceId: e.lmsCourseId).isCurrent
        }
        return (schedule + deadlines).sorted { $0.start < $1.start }
    }

    // MARK: Course hub (LMS)

    /// core_course_get_contents for one Moodle course.
    public func courseContents(lmsToken: String, courseId: Int) async throws -> [CourseSection] {
        LiveParsers.sections(try await lmsCall(lmsToken, "core_course_get_contents", [("courseid", "\(courseId)")]))
    }

    /// material_store.dart _authorize: the token is only ever sent to an https
    /// pluginfile URL on the LMS host — and here in a POST body, not the URL.
    public func downloadFile(_ file: CourseModule.File, lmsToken: String) async throws -> Data {
        guard file.url.scheme == "https", file.url.host == university.lmsBase.host,
              file.url.path.hasPrefix("/webservice/pluginfile.php/") else { throw LiveError.rejected("file url not allowed") }
        let res = try await transport.send(HTTPRequest(
            method: "POST", url: file.url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: FormBody.encode([("token", lmsToken)])))
        guard res.status == 200 else { throw LiveError.network("HTTP \(res.status)") }
        return res.body
    }
}

public enum LiveError: Error, Equatable, Sendable {
    case rejected(String)
    case network(String)

    var text: String {
        switch self {
        case .rejected(let s), .network(let s): return s
        }
    }
}

public struct SignInOutcome: Sendable {
    public init(snapshot: AcademicSnapshot?, sisError: String?, lmsError: String?) {
        self.snapshot = snapshot
        self.sisError = sisError
        self.lmsError = lmsError
    }

    public var snapshot: AcademicSnapshot?
    /// nil = that system signed in.
    public var sisError: String?
    public var lmsError: String?
    /// Moodle web-service token, kept in memory only (Android SessionTokens.lmsToken).
    public var lmsToken: String?
}

extension Result where Failure == LiveError {
    var value: Success? {
        switch self {
        case .success(let v): return v
        case .failure: return nil
        }
    }

    var errorText: String? {
        switch self {
        case .success: return nil
        case .failure(let e): return e.text
        }
    }
}
