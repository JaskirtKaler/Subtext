import SwiftUI
import SubtextCore

// Native dynamic colors and system type follow the editorial reference on every iPhone size.
enum Theme {
    static let blue = Color(red: 0, green: 0.35, blue: 0.78)
    static let red = Color(red: 0.85, green: 0.04, blue: 0.08)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemFill)
}

extension SpeakerColor {
    var tint: Color {
        switch self {
        case .blue: return Color(red: 0.25, green: 0.39, blue: 0.98)
        case .purple: return Color(red: 0.52, green: 0.32, blue: 0.91)
        case .green: return Color(red: 0.04, green: 0.60, blue: 0.45)
        case .orange: return Color.orange
        }
    }
}

extension View {
    func editorialCard(padding: CGFloat = 16) -> some View {
        self.padding(padding).background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    func sectionCaption() -> some View {
        self.font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(1.1)
    }
}

struct Pill: View {
    let title: String
    var color: Color = Theme.blue
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .foregroundStyle(color).background(color.opacity(0.09), in: Capsule())
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var color: Color = Theme.blue
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).frame(minWidth: 44, minHeight: 44) }
            .foregroundStyle(color).accessibilityLabel(label)
    }
}

struct WaveformView: View {
    var levels: [Float] = []
    var color: Color = Theme.blue
    var progress: Double = 0
    var isPlaceholder = false
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let count = max(1, Int(size.width / 5))
                for index in 0..<count {
                    let value: Double
                    if levels.isEmpty {
                        value = isPlaceholder ? 0.13 + abs(sin(Double(index) * 1.71) * cos(Double(index) * 0.28)) * 0.72 : 0.06
                    } else {
                        let mapped = min(levels.count - 1, index * levels.count / count)
                        value = max(0.04, min(1, Double(levels[mapped])))
                    }
                    let height = max(3, CGFloat(value) * (size.height - 8))
                    let rect = CGRect(x: CGFloat(index) * 5, y: (size.height - height) / 2, width: 2.8, height: height)
                    let tint = progress > 0 && Double(index) / Double(count) > progress ? Color.secondary.opacity(0.22) : color
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(tint))
                }
                if progress > 0 {
                    let x = size.width * max(0, min(1, progress))
                    context.fill(Path(CGRect(x: x, y: 0, width: 1.5, height: size.height)), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.blue).padding(.bottom, 4)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 20)
    }
}
