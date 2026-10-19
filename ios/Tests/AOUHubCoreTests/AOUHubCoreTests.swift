@testable import AOUHubCore
import XCTest

/// Runs on Linux/WSL with plain `swift test` (no iOS SDK, no device).
final class SharedResourcesTests: XCTestCase {
    /// The real repo /shared folder, the same files xtool bundles into the app.
    static let bundle = SharedBundle(baseURL: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../../shared").standardizedFileURL)

    func testIOSReadsItsOwnUpdateRepository() throws {
        let config = try Self.bundle.appConfig()
        XCTAssertEqual(config.ios.biometric, "faceID")
        XCTAssertNotEqual(config.ios.update.repository, config.platforms.android.update.repository)
        XCTAssertEqual(config.ios.update.latestReleaseUrl?.host, "api.github.com")
        XCTAssertTrue(config.ios.update.latestReleaseUrl!.path.contains(config.ios.update.repository))
    }

    func testTokensAndStringsLoad() throws {
        let tokens = try Self.bundle.tokens()
        XCTAssertEqual(tokens.color("brand", .light), ARGB(hex: "FF002D58"))
        XCTAssertEqual(tokens.gradient("hero", .dark).count, 3)
        let ar = try Self.bundle.localizer(.ar), en = try Self.bundle.localizer(.en)
        XCTAssertTrue(ar.isRightToLeft)
        XCTAssertEqual(en("lock.attemptsLeft", ["value": 2]), "2 attempts left")
    }

    func testDemoFixtureBuildsAFreshSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try Self.bundle.demoFixture().snapshot(now: now)
        XCTAssertEqual(snapshot.student.name, "Demo Student")
        XCTAssertEqual(snapshot.timeline.first?.start, now.addingTimeInterval(2 * 3600))
        XCTAssertFalse(snapshot.courses.isEmpty)
    }
}

final class TodayEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ type: EventType, _ hours: Double) -> TimelineItem {
        TimelineItem(id: "\(type)\(hours)", title: "", type: type, start: now.addingTimeInterval(hours * 3600),
                     end: nil, course: nil, location: nil)
    }

    func testUpNextIsTheNextLectureOrExam() {
        let items = [item(.assignment, 1), item(.lecture, 5), item(.exam, 3), item(.lecture, -1)]
        XCTAssertEqual(TodayEngine().upNext(items, now: now)?.id, item(.exam, 3).id)
    }

    func testPulseBucketsAndTimeLeftMatchAndroid() {
        XCTAssertEqual([0, 1, 2, 3, 10, 11].map { PluralCategory($0) }, [.zero, .one, .two, .few, .few, .many])
        XCTAssertEqual(TimeLeft(from: now, to: now.addingTimeInterval(-60)), .overdue)
        XCTAssertEqual(TimeLeft(from: now, to: now.addingTimeInterval(45 * 60)), .left(45, unit: "min"))
        XCTAssertEqual(TimeLeft(from: now, to: now.addingTimeInterval(2 * 3600)), .left(2, unit: "hour"))
        XCTAssertEqual(TimeLeft(from: now, to: now.addingTimeInterval(72 * 3600)), .left(3, unit: "day"))
    }

    func testAttentionPutsOverdueFirstAndIgnoresFarDeadlines() {
        let items = [item(.quiz, 10), item(.assignment, -5), item(.exam, 500), item(.lecture, 1)]
        XCTAssertEqual(TodayEngine().needsAttention(items, now: now).map(\.id), [item(.assignment, -5).id, item(.quiz, 10).id])
    }
}

final class AppVersionTests: XCTestCase {
    func testParsesAndCompares() {
        XCTAssertEqual(AppVersion("v1.2.0+5"), AppVersion("1.2"))
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("1.10.0")!)
        XCTAssertNil(AppVersion("latest"))
    }
}

final class UpdateServiceTests: XCTestCase {
    struct StubClient: HTTPClient {
        let body: String
        var status = 200
        func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, status: Int) {
            (Data(body.utf8), status)
        }
    }

    func service(_ body: String, status: Int = 200) throws -> GitHubReleaseUpdateService {
        let config = try SharedResourcesTests.bundle.appConfig().ios.update
        return GitHubReleaseUpdateService(config: config, client: StubClient(body: body, status: status))
    }

    func release(_ tag: String, page: String = "https://github.com/ssssoliman937-design/aouapp-ios/releases/tag/x") -> String {
        #"{"tag_name":"\#(tag)","body":"Notes","html_url":"\#(page)","draft":false,"prerelease":false}"#
    }

    func testNewerReleaseIsOffered() async throws {
        let result = try await service(release("v1.1.0")).check(current: AppVersion("1.0.0")!)
        guard case .available(let info) = result else { return XCTFail("expected an update") }
        XCTAssertEqual(info.version, AppVersion("1.1.0"))
        XCTAssertEqual(info.notes, "Notes")
    }

    func testSameVersionIsUpToDate() async throws {
        let result = try await service(release("1.0.0")).check(current: AppVersion("1.0.0")!)
        XCTAssertEqual(result, .upToDate)
    }

    func testForeignReleasePageFallsBackToTheConfiguredRepo() async throws {
        let result = try await service(release("2.0.0", page: "https://evil.example/x")).check(current: AppVersion("1.0.0")!)
        guard case .available(let info) = result else { return XCTFail("expected an update") }
        XCTAssertEqual(info.pageURL.host, "github.com")
        XCTAssertTrue(info.pageURL.path.hasPrefix("/ssssoliman937-design/aouapp-ios"))
    }

    func testHttpErrorsAndGarbageAreReported() async throws {
        do {
            _ = try await service("", status: 404).check(current: AppVersion("1.0.0")!)
            XCTFail("expected an error")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .http(404))
        }
        do {
            _ = try await service("{}").check(current: AppVersion("1.0.0")!)
            XCTFail("expected an error")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .malformed)
        }
    }

    func testSnoozeHidesOnlyThatVersionUntilItExpires() {
        let schedule = UpdateSchedule(intervalHours: 6)
        let now = Date()
        let snoozed = (version: "1.1.0", until: now.addingTimeInterval(60))
        XCTAssertFalse(schedule.shouldPrompt(for: AppVersion("1.1.0")!, snoozed: snoozed, now: now))
        XCTAssertTrue(schedule.shouldPrompt(for: AppVersion("1.2.0")!, snoozed: snoozed, now: now))
        XCTAssertTrue(schedule.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(schedule.shouldCheck(lastCheck: now, now: now.addingTimeInterval(3600)))
    }
}

final class AppLockMachineTests: XCTestCase {
    let policy = AppLockPolicy(relockAfter: 30, maxFailedAttempts: 3)

    func testLaunchLockedOnlyWhenEnabled() {
        XCTAssertFalse(AppLockMachine(enabled: false, policy: policy).state.locked)
        XCTAssertTrue(AppLockMachine(enabled: true, policy: policy).state.locked)
    }

    func testFailuresRunOutIntoSignOut() {
        var lock = AppLockMachine(enabled: true, policy: policy)
        for _ in 0..<3 {
            XCTAssertTrue(lock.beginUnlock())
            lock.finishUnlock(.failed)
        }
        XCTAssertTrue(lock.exhausted)
        XCTAssertFalse(lock.beginUnlock())
        XCTAssertTrue(lock.state.locked)
    }

    func testCancelCostsNothingAndSuccessUnlocks() {
        var lock = AppLockMachine(enabled: true, policy: policy)
        _ = lock.beginUnlock()
        lock.finishUnlock(.cancelled)
        XCTAssertEqual(lock.state.error, .cancelled)
        XCTAssertEqual(lock.attemptsLeft, 3)
        _ = lock.beginUnlock()
        lock.finishUnlock(.success)
        XCTAssertFalse(lock.state.locked)
        XCTAssertNil(lock.state.error)
    }

    func testRelocksOnlyAfterThePolicyTime() {
        var lock = AppLockMachine(enabled: true, policy: policy)
        _ = lock.beginUnlock()
        lock.finishUnlock(.success)
        let t0 = Date()
        lock.didEnterBackground(at: t0)
        lock.willEnterForeground(at: t0.addingTimeInterval(29))
        XCTAssertFalse(lock.state.locked)
        lock.didEnterBackground(at: t0)
        lock.willEnterForeground(at: t0.addingTimeInterval(30))
        XCTAssertTrue(lock.state.locked)
    }

    func testNotEnrolledExhaustsImmediately() {
        var lock = AppLockMachine(enabled: true, policy: policy)
        _ = lock.beginUnlock()
        lock.finishUnlock(.notEnrolled)
        XCTAssertTrue(lock.exhausted)
        XCTAssertEqual(AppLockMachine.enableError(for: .success), nil)
        XCTAssertEqual(AppLockMachine.enableError(for: .lockout), .lockout)
    }
}
