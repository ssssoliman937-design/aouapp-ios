import AOUHubCore
import Foundation
import SwiftUI

/// Composition root and app-wide state. Views read it; all rules live in
/// AOUHubCore (AppLockMachine, TodayEngine, GitHubReleaseUpdateService).
@MainActor
final class AppModel: ObservableObject {
    enum Session: Equatable {
        case signedOut
        case signedIn(AcademicSnapshot)
    }

    enum UpdateStatus: Equatable {
        case idle, checking, upToDate, failed
    }

    @Published private(set) var session: Session = .signedOut
    @Published private(set) var lock: AppLockState
    @Published private(set) var updateStatus: UpdateStatus = .idle
    @Published var pendingUpdate: ReleaseInfo?
    /// Short, self-dismissing message (e.g. "signed in to SIS only").
    @Published var notice: String?
    @Published var language: Localizer.Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    let tokens: DesignTokens
    let currentVersion: AppVersion
    let today = TodayEngine()
    let biometricStatus: BiometricStatus

    private var machine: AppLockMachine
    private let localizers: [Localizer.Language: Localizer]
    private let repository: AcademicRepository
    private let authenticator: BiometricAuthenticator
    private let updates: UpdateService
    private let schedule: UpdateSchedule
    private let lockStore: LockPreferenceStore

    private enum Keys {
        static let language = "language"
        static let lastUpdateCheck = "update_last_check"
        static let snoozedVersion = "update_snoozed_version"
        static let snoozedUntil = "update_snoozed_until"
    }

    init(
        bundle: SharedBundle,
        repository: AcademicRepository,
        authenticator: BiometricAuthenticator,
        updates: (SharedAppConfig.Update) -> UpdateService,
        lockStore: LockPreferenceStore,
        currentVersion: AppVersion
    ) throws {
        let config = try bundle.appConfig()
        tokens = try bundle.tokens()
        localizers = Dictionary(uniqueKeysWithValues: try Localizer.Language.allCases.map { ($0, try bundle.localizer($0)) })
        let stored = UserDefaults.standard.string(forKey: Keys.language).flatMap(Localizer.Language.init(rawValue:))
        language = stored ?? .ar
        self.repository = repository
        self.authenticator = authenticator
        self.updates = updates(config.ios.update)
        self.lockStore = lockStore
        self.currentVersion = currentVersion
        schedule = UpdateSchedule(intervalHours: config.ios.update.checkIntervalHours)
        biometricStatus = authenticator.status()
        machine = AppLockMachine(
            enabled: lockStore.isEnabled(default: config.appLock.defaultEnabled),
            policy: config.lockPolicy
        )
        lock = machine.state
    }

    var t: Localizer { localizers[language]! }
    var lockExhausted: Bool { machine.exhausted }
    var attemptsLeft: Int { machine.attemptsLeft }

    /// Only a signed-in student is ever covered by the lock.
    var showsLock: Bool {
        if case .signedIn = session { return lock.locked }
        return false
    }

    // MARK: Session

    /// Real SIS + LMS sign-in. Returns an error message, or nil once signed in
    /// (a one-system failure still signs in and shows a `notice`).
    func signIn(studentId: String, sisPassword: String, lmsPassword: String) async -> String? {
        guard !studentId.trimmingCharacters(in: .whitespaces).isEmpty, !(sisPassword.isEmpty && lmsPassword.isEmpty) else {
            return t("login.error.empty")
        }
        let outcome = await repository.signIn(studentId: studentId, sisPassword: sisPassword,
                                              lmsPassword: lmsPassword, arabic: language == .ar)
        guard let snapshot = outcome.snapshot else {
            return "\(t("login.error.failed"))\n\(t("login.error.detail", ["sis": outcome.sisError ?? "ok", "lms": outcome.lmsError ?? "ok"]))"
        }
        machine.signedInWithPassword()
        lock = machine.state
        session = .signedIn(snapshot)
        lmsToken = outcome.lmsToken
        if let error = outcome.sisError {
            notice = t("login.partial.sisFailed", ["error": error])
        } else if let error = outcome.lmsError {
            notice = t("login.partial.lmsFailed", ["error": error])
        }
        return nil
    }

    func signInDemo() async {
        if let snapshot = try? await repository.demo() { session = .signedIn(snapshot) }
    }

    // MARK: Course hub (LMS)

    /// In memory only, like Android's SessionTokens; dropped on sign-out.
    private var lmsToken: String?

    var canLoadContent: Bool { lmsToken != nil }

    func contents(of course: Course) async throws -> [CourseSection] {
        guard let lmsToken, let id = course.lmsCourseId else { return [] }
        return try await repository.courseContents(lmsToken: lmsToken, courseId: id)
    }

    /// Downloads into the app's private temp folder and returns the local file for Quick Look.
    func download(_ file: CourseModule.File) async throws -> URL {
        guard let lmsToken else { throw URLError(.userAuthenticationRequired) }
        let data = try await repository.downloadFile(file, lmsToken: lmsToken)
        let safeName = file.name.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName.isEmpty ? "file" : safeName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func signOut() {
        lmsToken = nil
        machine.disable()
        lockStore.setEnabled(false)
        lock = machine.state
        session = .signedOut
    }

    // MARK: Lock

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background: machine.didEnterBackground(at: Date())
        case .active: machine.willEnterForeground(at: Date())
        default: break
        }
        lock = machine.state
    }

    func unlock() async {
        guard machine.beginUnlock() else { return }
        lock = machine.state
        let outcome = await authenticator.authenticate(reason: t("lock.subtitle.faceID"))
        machine.finishUnlock(outcome)
        lock = machine.state
    }

    /// Returns a message when the lock could not be turned on.
    func setLockEnabled(_ enabled: Bool) async -> String? {
        guard enabled else {
            machine.disable()
            lockStore.setEnabled(false)
            lock = machine.state
            return nil
        }
        let outcome = await authenticator.authenticate(reason: t("settings.lock.faceID"))
        if let error = AppLockMachine.enableError(for: outcome) {
            return error == .cancelled ? nil : t("lock.error.\(error.rawValue)")
        }
        machine.enableConfirmed()
        lockStore.setEnabled(true)
        lock = machine.state
        return nil
    }

    // MARK: Updates (iOS repository only)

    func checkForUpdates(userInitiated: Bool) async {
        let defaults = UserDefaults.standard
        let now = Date()
        let last = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        guard userInitiated || schedule.shouldCheck(lastCheck: last, now: now) else { return }

        updateStatus = .checking
        do {
            let result = try await updates.check(current: currentVersion)
            defaults.set(now, forKey: Keys.lastUpdateCheck)
            switch result {
            case .upToDate:
                updateStatus = .upToDate
            case .available(let release):
                updateStatus = .idle
                if userInitiated || schedule.shouldPrompt(for: release.version, snoozed: snoozed(), now: now) {
                    pendingUpdate = release
                }
            }
        } catch {
            updateStatus = .failed
        }
    }

    func snoozeUpdate() {
        guard let release = pendingUpdate else { return }
        let defaults = UserDefaults.standard
        defaults.set(release.version.description, forKey: Keys.snoozedVersion)
        defaults.set(Date().addingTimeInterval(schedule.snooze), forKey: Keys.snoozedUntil)
        pendingUpdate = nil
    }

    private func snoozed() -> (version: String, until: Date)? {
        let defaults = UserDefaults.standard
        guard let version = defaults.string(forKey: Keys.snoozedVersion),
              let until = defaults.object(forKey: Keys.snoozedUntil) as? Date else { return nil }
        return (version, until)
    }
}

extension AppModel {
    /// Production wiring: /shared from the .app bundle, the university's SIS/LMS, Face ID, GitHub.
    static func live() -> AppModel {
        let bundle = SharedBundle(baseURL: Bundle.main.bundleURL)
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init) ?? AppVersion("0.0.0")!
        do {
            let university = try bundle.appConfig().university
            return try AppModel(
                bundle: bundle,
                repository: UniversityAcademicRepository(
                    bundle: bundle,
                    client: UniversityClient(university: university, transport: URLSessionTransport())),
                authenticator: FaceIDAuthenticator(),
                updates: { GitHubReleaseUpdateService(config: $0, client: URLSessionHTTPClient()) },
                lockStore: UserDefaultsLockPreferenceStore(),
                currentVersion: version
            )
        } catch {
            // /shared is part of the build (xtool.yml resources); missing means a broken package.
            fatalError("AOU Hub: shared resources missing from the app bundle: \(error)")
        }
    }
}
