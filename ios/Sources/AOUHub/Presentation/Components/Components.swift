import AOUHubCore
import SwiftUI

/// V5Group: rounded elevated container (android/lib/ui/widgets/v5_components.dart).
struct V5Group<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(palette.isDark ? 0 : 0.06), radius: 3, y: 1)
    }
}

/// Small section label above a group ("درجات هذا الفصل").
struct V5SectionLabel: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.body(14, weight: .semibold))
            .foregroundStyle(palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
    }
}

/// Kicker + big title + optional "See all", as on Today.
struct SectionHead: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let kicker: String
    let title: String
    var seeAll: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker).font(AppFont.body(12, weight: .bold)).foregroundStyle(palette.accent)
                Text(title).font(AppFont.body(24, weight: .bold)).foregroundStyle(palette.text)
            }
            Spacer()
            if let seeAll {
                Button(model.t("today.seeAll"), action: seeAll)
                    .font(AppFont.body(15)).foregroundStyle(palette.accent)
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 6)
    }
}

/// Large page title with an optional trailing accessory (term pill, buttons).
struct LargeHead<Accessory: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title).font(AppFont.body(34, weight: .bold)).foregroundStyle(palette.text)
            Spacer()
            accessory
        }
    }
}

struct TermPill: View {
    @Environment(\.palette) private var palette
    let term: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text(term).environment(\.layoutDirection, .leftToRight)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(AppFont.body(14, weight: .bold))
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 14).frame(height: 36)
        .background(palette.accentSoft, in: Capsule())
    }
}

struct Pill: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .font(AppFont.body(12, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }
}

/// Priority row: level bar, when-box (! overdue or N unit), title, code · day · time, type badge.
struct PriorityRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let item: TimelineItem

    var body: some View {
        let left = TimeLeft(from: Date(), to: item.start)
        let typeTone = palette.toneName(for: item.type)
        let tone: String = {
            if case .left(_, let unit) = left, unit == "day" || item.type == .quiz { return typeTone }
            return "urgent"
        }()
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(palette.tone(tone)).frame(width: 4).padding(.vertical, 2)
            VStack(spacing: 0) {
                switch left {
                case .overdue:
                    Text("!").font(AppFont.body(19, weight: .bold))
                    Text(model.t("today.overdue")).font(AppFont.body(11, weight: .semibold))
                case .left(let n, let unit):
                    Text("\(n)").font(AppFont.body(19, weight: .bold)).monospacedDigit()
                    Text(model.t("today.unit.\(unit)")).font(AppFont.body(11, weight: .semibold))
                }
            }
            .foregroundStyle(palette.tone(tone))
            .frame(width: 50, height: 54)
            .background(palette.tone(tone + "Soft"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(AppFont.body(16, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                HStack(spacing: 8) {
                    if let course = item.course {
                        Text(course).font(AppFont.body(13, weight: .bold)).foregroundStyle(palette.accent)
                    }
                    Text(item.start, format: .dateTime.weekday(.wide).hour().minute())
                        .font(AppFont.body(13)).foregroundStyle(palette.text2).lineLimit(1)
                    Pill(text: model.t("type.\(item.type.rawValue)"), fg: palette.tone(typeTone), bg: palette.tone(typeTone + "Soft"))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(palette.text3)
        }
        .padding(14)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(palette.isDark ? 0 : 0.06), radius: 3, y: 1)
    }
}

/// Settings-style row with a colored icon square (V5Row).
struct V5Row<Trailing: View>: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let iconColor: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body(16, weight: .bold)).foregroundStyle(palette.text)
                if let subtitle { Text(subtitle).font(AppFont.body(13)).foregroundStyle(palette.text2) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

/// Page scaffold: V5 background + scrolling content above the floating dock.
struct Page<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(palette.bg.ignoresSafeArea())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body(18, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(palette.cta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
