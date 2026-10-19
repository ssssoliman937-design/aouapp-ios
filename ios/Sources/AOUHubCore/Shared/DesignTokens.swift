import Foundation

/// shared/design/tokens.json. Colors stay ARGB strings until the UI layer
/// turns them into SwiftUI colors, so this file needs no UI framework.
public struct DesignTokens: Decodable, Sendable {
    public enum Mode: String, Sendable { case light, dark }

    public struct Radius: Decodable, Sendable {
        public let xs, sm, md, lg, xl: Double
    }

    public struct Spacing: Decodable, Sendable {
        public let gutter, sectionGap: Double
    }

    public let navy: [String: String]
    public let radius: Radius
    public let spacing: Spacing
    private let color: [String: [String: ColorValue]]

    public func color(_ name: String, _ mode: Mode) -> ARGB? {
        guard case .single(let hex)? = color[mode.rawValue]?[name] else { return nil }
        return ARGB(hex: hex)
    }

    public func gradient(_ name: String, _ mode: Mode) -> [ARGB] {
        guard case .list(let hexes)? = color[mode.rawValue]?[name] else { return [] }
        return hexes.compactMap(ARGB.init(hex:))
    }

    private enum ColorValue: Decodable, Sendable {
        case single(String)
        case list([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([String].self) {
                self = .list(list)
            } else {
                self = .single(try container.decode(String.self))
            }
        }
    }
}

/// A color as 0...1 components, parsed from "AARRGGBB".
public struct ARGB: Equatable, Sendable {
    public let alpha, red, green, blue: Double

    public init?(hex: String) {
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        alpha = Double((value >> 24) & 0xFF) / 255
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}
