import Foundation

/// Reads files from /shared. In the app the base is the .app bundle (xtool
/// copies ../shared/* to its root); in tests it is the repo's shared folder.
public struct SharedBundle: Sendable {
    public enum LoadError: Error, Equatable {
        case missing(String)
    }

    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func data(_ relativePath: String) throws -> Data {
        let url = baseURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else {
            throw LoadError.missing(relativePath)
        }
        return data
    }

    public func appConfig() throws -> SharedAppConfig {
        try JSONDecoder().decode(SharedAppConfig.self, from: data("config/app.json"))
    }

    public func tokens() throws -> DesignTokens {
        try JSONDecoder().decode(DesignTokens.self, from: data("design/tokens.json"))
    }

    public func localizer(_ language: Localizer.Language) throws -> Localizer {
        let table = try JSONDecoder().decode([String: String].self, from: data("l10n/\(language.rawValue).json"))
        return Localizer(language: language, table: table)
    }

    public func demoFixture() throws -> DemoFixture {
        try JSONDecoder().decode(DemoFixture.self, from: data("fixtures/demo.json"))
    }
}
