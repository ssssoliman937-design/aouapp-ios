@testable import AOUHubCore
import XCTest

/// Same cases as simulator/test/live.test.mjs, against a fake transport.
final class UniversityClientTests: XCTestCase {
    final class FakeTransport: HTTPTransport, @unchecked Sendable {
        var sisOK = true
        var lmsOK = true
        private(set) var requests: [HTTPRequest] = []
        private let lock = NSLock()

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.lock(); requests.append(request); lock.unlock()
            let path = request.url.path
            func json(_ object: Any, headers: [String: String] = [:]) throws -> HTTPResponse {
                HTTPResponse(status: 200, headers: headers, body: try JSONSerialization.data(withJSONObject: object))
            }
            if path.hasSuffix("GetStudentByCredentials") {
                return sisOK
                    ? try json(["IsValid": true, "data": [
                        "Id": "20000001", "StudentEnglishName": "Sara Ahmed Ali", "StudentArabicName": "سارة أحمد علي",
                        "AcademicYear": 2025.0, "AcademicSem": 1.0, "Token": "---", "GPA": 3.41,
                        "StudentCreditsCompleted": 60, "StudentPlanCredits": 130,
                    ] as [String: Any]], headers: ["Set-Cookie": "_spaoutkn=abc.def.ghi; path=/; secure; SameSite=Strict"])
                    : try json(["IsValid": false, "Id": "", "Error": "Invalid User name or Password"] as [String: Any])
            }
            if path.hasSuffix("GetStudentAcademicSessions") {
                return try json([
                    ["Id": "old", "AcademicYear": 2024, "AcademicSem": 3, "AcademicSessionNameDetailed": "Summer 2024/2025"],
                    ["Id": "s-cur", "AcademicYear": 2025, "AcademicSem": 1, "AcademicSessionNameDetailed": "First 2025/2026"],
                ])
            }
            if path.hasSuffix("GetStudentDetailedGrades") {
                return try json(["IsValid": true, "data": [
                    ["Coursecode": "2526-GT101 (01)", "Credits": 3, "Grade": "Grade Pending", "Gradedetails": "TMA (17/20);Mid Term Assessment (24/30)"],
                    ["Coursecode": "MT101", "Credits": "3", "Grade": "B+", "Gradedetails": "TMA (14/20);Mid Term Assessment (22/30);Final Exam (41/50)"],
                ]] as [String: Any])
            }
            if path.hasSuffix("GetStudentSchedules") {
                return try json([
                    ["date": "2026-10-20", "Start_Time": "11:30", "End_Time": "13:30", "Event_Type": "1", "Course_Part_Code": "GT101", "E_Location_Name": "FE17"],
                    ["date": "2026-10-25", "Start_Time": "2:00 PM", "Event_Type": "2", "Exam_Name": "Final Exam MT101", "Course_Part_Code": "MT101"],
                ])
            }
            if path.hasSuffix("token.php") {
                return lmsOK ? try json(["token": "tok123"]) : try json(["error": "Invalid login, please try again", "errorcode": "invalidlogin"])
            }
            let form = String(decoding: request.body ?? Data(), as: UTF8.self)
            if form.contains("core_webservice_get_site_info") { return try json(["userid": 77]) }
            if form.contains("core_enrol_get_users_courses") { return try json([["id": 11, "shortname": "GT101-2526", "fullname": "Information Technology"]]) }
            return try json(["events": [["name": "TMA 2 is due", "modulename": "assign", "timesort": 1_800_000_000, "course": ["shortname": "GT101", "id": 11]]]])
        }
    }

    let university = SharedAppConfig.University(
        sisBase: URL(string: "https://sis.example/SPAPIEGY")!, lmsBase: URL(string: "https://lms.example")!, lmsService: "moodle_mobile_app")

    func testSendsTheSameAuthAsAndroid() async throws {
        let transport = FakeTransport()
        let outcome = await UniversityClient(university: university, transport: transport)
            .signIn(studentId: "20000001", sisPassword: "p1", lmsPassword: "p2", arabic: false)
        XCTAssertNil(outcome.sisError)
        XCTAssertNil(outcome.lmsError)
        let get = try XCTUnwrap(transport.requests.first { $0.url.path.hasSuffix("GetStudentAcademicSessions") })
        XCTAssertEqual(get.headers["cookie"], "_spaoutkn=abc.def.ghi")
        XCTAssertEqual(get.headers["Authorization"], "---")
        let std = try XCTUnwrap(get.headers["stdtoken"].flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(String(decoding: std, as: UTF8.self), #"{"StudentId":"20000001","AcademicYear":2025,"AcademicSem":1}"#)
        XCTAssertTrue(transport.requests.contains { $0.url.query?.contains("AcademicSessionId=s-cur") == true })
        // Passwords only in POST bodies, never in a URL.
        XCTAssertFalse(transport.requests.contains { $0.url.absoluteString.contains("p1") || $0.url.absoluteString.contains("p2") })
    }

    func testLiveSnapshotHasTheDemoShape() async throws {
        let outcome = await UniversityClient(university: university, transport: FakeTransport())
            .signIn(studentId: "1", sisPassword: "a", lmsPassword: "b", arabic: false)
        let s = try XCTUnwrap(outcome.snapshot)
        XCTAssertEqual(s.student.firstName, "Sara")
        XCTAssertEqual(s.student.initials, "SA")
        XCTAssertEqual(s.student.term, "First 2025/2026")
        // GradeMath.gpaOf: GT101 pending (no band), MT101 B+ = 3.5; every term feeds the trend.
        XCTAssertEqual(s.student.termGpa, 3.5)
        XCTAssertEqual(s.student.gpaHistory, [3.5, 3.5])
        XCTAssertEqual(s.grades.map(\.code), ["GT101", "MT101"])
        XCTAssertEqual(s.grades.first?.final, nil)
        XCTAssertEqual(s.courses.map(\.code), ["GT101", "MT101"])
        XCTAssertEqual(s.courses.map(\.onLms), [true, false])
        let lecture = try XCTUnwrap(s.timeline.first { $0.type == .lecture })
        XCTAssertEqual(Calendar.current.component(.hour, from: lecture.start), 11)
        let exam = try XCTUnwrap(s.timeline.first { $0.type == .exam })
        XCTAssertEqual(Calendar.current.component(.hour, from: exam.start), 14, "2:00 PM parses to 14:00")
        XCTAssertTrue(s.timeline.contains { $0.type == .assignment && $0.course == "GT101" })
    }

    func testOneSystemFailingStillSignsInBothFailingDoesNot() async {
        let lmsDown = FakeTransport()
        lmsDown.lmsOK = false
        let partial = await UniversityClient(university: university, transport: lmsDown)
            .signIn(studentId: "1", sisPassword: "a", lmsPassword: "x", arabic: false)
        XCTAssertNotNil(partial.snapshot)
        XCTAssertEqual(partial.lmsError, "Invalid login, please try again")

        let bothDown = FakeTransport()
        bothDown.sisOK = false
        bothDown.lmsOK = false
        let none = await UniversityClient(university: university, transport: bothDown)
            .signIn(studentId: "1", sisPassword: "x", lmsPassword: "x", arabic: false)
        XCTAssertNil(none.snapshot)
        XCTAssertEqual(none.sisError, "Invalid User name or Password")
    }

    func testTileColorIsAndroidsDartHash() {
        // Values printed by `dart` for "<code>".hashCode.
        let dart: [String: UInt32] = ["MT131": 518_652_302, "MT101": 622_889_049, "MST129": 76_268_640, "EL111": 860_400_252,
                                      "GT101": 871_676_982, "GR118": 1_024_294_163, "EL099": 233_687_149, "GB102": 117_211_779]
        for (code, hash) in dart { XCTAssertEqual(LiveParsers.dartStringHash(code), hash, code) }
        XCTAssertEqual(["GT101", "GR118", "EL099", "MT101"].map(LiveParsers.tone(for:)), ["accent", "brand", "ok", "info"])
    }

    func testWithheldGradesAndGradeMath() {
        let withheld = Grade(code: "EL111", creditHours: 3, status: "--Cannot view: Unsettled Balance 11;", tma: nil, mid: nil, final: nil)
        XCTAssertTrue(withheld.withheld)
        XCTAssertEqual(withheld.statusLabel, "Unsettled Balance 11")
        XCTAssertFalse(withheld.isPending)
        let a = Grade(code: "A1", creditHours: 3, status: "A", tma: nil, mid: nil, final: nil)
        let c = Grade(code: "C1", creditHours: 3, status: "C", tma: nil, mid: nil, final: nil)
        XCTAssertEqual(GradeMath.gpaOf([a, c]), 3)
        XCTAssertNil(GradeMath.gpaOf([withheld]))
        let earned = Grade(code: "X", creditHours: 3, status: "Grade Pending", tma: 20, mid: 20, final: 41)
        XCTAssertEqual(GradeMath.bandOf(earned)?.letter, "B")
    }

    func testCourseNameAndCurrentInstance() {
        XCTAssertEqual(LiveParsers.cleanCourseName("[MT131] Discrete Mathematics", code: "MT131"), "Discrete Mathematics")
        let now = Date(timeIntervalSince1970: 86_400_000)
        let old = LiveParsers.LMSInstance(id: 1, name: "old", start: now.addingTimeInterval(-300 * 86_400), end: now.addingTimeInterval(-200 * 86_400))
        let cur = LiveParsers.LMSInstance(id: 2, name: "cur", start: now.addingTimeInterval(-20 * 86_400), end: now.addingTimeInterval(60 * 86_400))
        XCTAssertEqual(LiveParsers.pickCurrentInstance([old, cur], now: now)?.id, 2)
        XCTAssertEqual(LiveParsers.pickCurrentInstance([cur, old], now: now)?.id, 2)
    }

    func testCourseContentsParse() {
        let raw: [Any] = [
            ["name": "Week 1", "modules": [
                ["id": 5, "name": "Lecture 1 slides.pdf", "modname": "resource", "url": "https://lms/mod/resource/view.php?id=5",
                 "contents": [["type": "file", "filename": "l1.pdf", "fileurl": "https://lms/webservice/pluginfile.php/1/l1.pdf", "filesize": 2_400_000]]],
                ["id": 6, "name": "TMA 1", "modname": "assign", "dates": [["label": "Due:", "timestamp": 1_800_000_000]]],
                ["id": 7, "name": "", "modname": "label"],
            ]] as [String: Any],
            ["name": "Empty", "modules": [Any]()] as [String: Any],
        ]
        let sections = LiveParsers.sections(raw)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].modules.map(\.modname), ["resource", "assign"])
        XCTAssertEqual(sections[0].modules[0].primaryFile?.size, 2_400_000)
        XCTAssertEqual(sections[0].modules[1].due, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testParsersMatchModelsDart() {
        XCTAssertEqual(LiveParsers.normalizeCode("2526-GT101 (01)"), "GT101")
        XCTAssertEqual(LiveParsers.normalizeCode(" mst129-2526 "), "MST129")
        let g = LiveParsers.parseGradeDetails("TMA (0/20);Mid Term Assessment (19/30);Final Exam (33/50)")
        XCTAssertEqual([g.tma, g.mid, g.final], [0, 19, 33])
        XCTAssertEqual(LiveParsers.eventType("assign"), .assignment)
        XCTAssertEqual(LiveParsers.eventType("course"), .event)
        XCTAssertEqual(LiveParsers.tone(for: "GT101"), LiveParsers.tone(for: "GT101"))
    }
}
