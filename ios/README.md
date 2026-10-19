# AOU Hub — iOS (SwiftUI, built with xtool)

Native iPhone version of the Android app, built and signed on Linux / Windows WSL
with [xtool](https://github.com/xtool-org/xtool) — no Mac, no Xcode app.

## Layout

```
ios/
  Package.swift            two targets (below)
  xtool.yml                bundle id, Info.plist, icon, and ../shared/* as resources
  Info.plist               Face ID usage text, Cairo font, version
  Sources/AOUHubCore/      Foundation only — runs under `swift test` on Linux
    Shared/                SharedBundle, SharedAppConfig, DesignTokens, Localizer
    Domain/                Models, TodayEngine
    Data/                  AcademicRepository, DemoFixture
    Live/                  UniversityClient (SIS cookie + stdtoken, Moodle token), LiveParsers, HTTPTransport
    Update/                AppVersion, GitHubReleaseUpdateService, UpdateSchedule
    Security/              AppLockMachine, BiometricAuthenticator, LockPreferenceStore
  Sources/AOUHub/          SwiftUI app
    App/                   AOUHubApp (@main), AppModel (composition root), RootView
    Platform/              FaceIDAuthenticator (LocalAuthentication), URLSessionHTTPClient, URLSessionTransport
    Presentation/          Login, Shell (tabs), Screens, Lock, Update, Components, Theme
  Tests/AOUHubCoreTests/   config, tokens, l10n, update service, lock machine, live SIS/LMS client
  scripts/                 setup-wsl.sh · check-shared.sh · build.sh · run-device.sh
```

## Shared resources (no copies)

`xtool.yml` lists `../shared/config`, `design`, `l10n`, `fixtures`, `fonts` as
root resources, so xtool copies them into `AOUHub.app/` at build time.
`AppModel.live()` reads them with `SharedBundle(baseURL: Bundle.main.bundleURL)`.
`scripts/check-shared.sh` fails if a shared file is ever copied into `/ios` or the
bundle id drifts from `shared/config/app.json`.

## Updates — iOS repository only

`platforms.ios.update` in `shared/config/app.json` points at
`ssssoliman937-design/aouapp-ios` (separate from Android's `aouapp`).
`GitHubReleaseUpdateService` reads `releases/latest`, compares `tag_name` with
`CFBundleShortVersionString`, and shows `UpdatePromptView`. "Update now" opens the
release page (iOS cannot self-install a sideloaded `.ipa`); "Later" snoozes that
version for 24 h. Checks run on foreground at most every 6 h, or from Settings.

Publish a release: bump `CFBundleShortVersionString` in `Info.plist`, run
`scripts/build.sh --release`, then create a GitHub release in `aouapp-ios` with
tag `v<version>` and attach `ios/xtool/AOUHub.ipa`.

## Face ID lock

`FaceIDAuthenticator` uses `.deviceOwnerAuthenticationWithBiometrics` and reports
`noHardware` on non-Face-ID devices. `AppLockMachine` locks on launch and after
30 s in the background (`appLock` in shared config); 3 failures or "not enrolled"
leave only "Sign out". Toggle: Settings → Security.

## Build

```bash
ios/scripts/setup-wsl.sh        # once: Swift, usbmuxd, xtool, Apple login, SDK from Xcode.xip
swift test --package-path ios   # core logic, no device needed
ios/scripts/build.sh            # debug .app
ios/scripts/build.sh --release  # signed .ipa
ios/scripts/run-device.sh       # install + launch on a USB iPhone
```

No iPhone? Use `/simulator` (see its README) for Face ID, update and navigation flows.

## Phase status

| Feature | Status |
|---|---|
| Tabs: Today / Courses / Planner / Grades / Settings | done, V5 design matching the Android goldens |
| Real SIS + LMS sign-in (separate passwords) + current term grades, schedule, courses, LMS deadlines | done (`AOUHubCore/Live`, same calls as Android's auth_repository.dart) |
| Face ID lock, launch + resume, toggle, fallbacks | done |
| Update check from the iOS repository + prompt | done |
| Arabic/English, RTL, Cairo font, V5 tokens | done |
| Session restore without passwords, background sync, push, materials, admin | next phase |
