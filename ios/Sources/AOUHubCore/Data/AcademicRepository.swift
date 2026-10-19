import Foundation

/// Data boundary for everything academic. The UI never knows whether the
/// snapshot came from the university or from the demo fixture.
public protocol AcademicRepository: Sendable {
    /// SIS and LMS each take their own password; either one may fail alone.
    func signIn(studentId: String, sisPassword: String, lmsPassword: String, arabic: Bool) async -> SignInOutcome
    func demo() async throws -> AcademicSnapshot
    /// Course hub content (core_course_get_contents).
    func courseContents(lmsToken: String, courseId: Int) async throws -> [CourseSection]
    func downloadFile(_ file: CourseModule.File, lmsToken: String) async throws -> Data
}

/// Live university sign-in (UniversityClient) + the shared demo fixture for "Continue as guest".
public struct UniversityAcademicRepository: AcademicRepository {
    private let bundle: SharedBundle
    private let client: UniversityClient
    private let now: @Sendable () -> Date

    public init(bundle: SharedBundle, client: UniversityClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.bundle = bundle
        self.client = client
        self.now = now
    }

    public func signIn(studentId: String, sisPassword: String, lmsPassword: String, arabic: Bool) async -> SignInOutcome {
        await client.signIn(studentId: studentId.trimmingCharacters(in: .whitespaces),
                            sisPassword: sisPassword, lmsPassword: lmsPassword, arabic: arabic, now: now())
    }

    public func demo() async throws -> AcademicSnapshot {
        try bundle.demoFixture().snapshot(now: now())
    }

    public func courseContents(lmsToken: String, courseId: Int) async throws -> [CourseSection] {
        try await client.courseContents(lmsToken: lmsToken, courseId: courseId)
    }

    public func downloadFile(_ file: CourseModule.File, lmsToken: String) async throws -> Data {
        try await client.downloadFile(file, lmsToken: lmsToken)
    }
}
