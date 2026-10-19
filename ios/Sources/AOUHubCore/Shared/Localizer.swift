import Foundation

/// shared/l10n/<lang>.json with `{name}` placeholders. A missing key renders
/// as the key itself so a gap is visible instead of blank.
public struct Localizer: Sendable {
    public enum Language: String, Sendable, CaseIterable {
        case ar, en
    }

    public let language: Language
    private let table: [String: String]

    public init(language: Language, table: [String: String]) {
        self.language = language
        self.table = table
    }

    public var isRightToLeft: Bool { language == .ar }

    public func callAsFunction(_ key: String, _ args: [String: CustomStringConvertible] = [:]) -> String {
        var text = table[key] ?? key
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return text
    }
}
