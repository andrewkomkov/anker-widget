import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let state: ChargerState?
    var stale: Bool {
        guard let s = state else { return true }
        return !s.connected || date.timeIntervalSince(s.date) > SharedStore.staleAfter
    }
}

extension PadKind {
    /// Full scale of the ring: phone pad is Qi2.2 25 W, the others give a few watts.
    var maxWatts: Double { self == .phone ? 25 : 5 }
}

enum Palette {
    static let charge = Color(red: 0.36, green: 0.93, blue: 0.55)
    static let bolt = Color(red: 1.0, green: 0.80, blue: 0.25)
}

struct WidgetBackground: View {
    let total: Double

    var body: some View {
        let glow = min(total / 15, 1)
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.13, blue: 0.17), Color(red: 0.04, green: 0.05, blue: 0.07)],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Palette.charge.opacity(0.10 + 0.30 * glow), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 220)
            RadialGradient(
                colors: [Color.cyan.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 180)
        }
    }
}

struct PadRing: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let pad: Pad
    let size: CGFloat
    let showsLabel: Bool

    var body: some View {
        let kind = pad.kind ?? .other
        let fraction = pad.isCharging ? max(min(pad.watts / kind.maxWatts, 1), 0.04) : 0
        let full = renderingMode == .fullColor
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: size * 0.09)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        full ? AnyShapeStyle(Palette.charge.gradient) : AnyShapeStyle(.primary),
                        style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(pad.isCharging ? .white : .white.opacity(0.35))
                if pad.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(full ? Palette.bolt : .primary)
                        .padding(size * 0.05)
                        .background(Circle().fill(Color(red: 0.07, green: 0.08, blue: 0.11)))
                        .offset(x: size * 0.36, y: -size * 0.36)
                        .widgetAccentable()
                }
            }
            .frame(width: size, height: size)

            if showsLabel {
                Text(pad.isCharging ? formatWatts(pad.watts) : "—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(pad.isCharging ? .white : .white.opacity(0.4))
                    .contentTransition(.numericText())
            }
        }
    }
}

struct ChargerWidgetContent: View {
    let entry: Entry
    let family: WidgetFamily

    var body: some View {
        Group {
            if let s = entry.state, !s.pads.isEmpty {
                if family == .systemSmall { small(s) } else { medium(s) }
            } else {
                empty
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func header(_ s: ChargerState, big: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: entry.stale ? "bolt.slash.fill" : "bolt.fill")
                .font(.system(size: big ? 15 : 13, weight: .bold))
                .foregroundStyle(entry.stale ? .white.opacity(0.4) : Palette.bolt)
                .widgetAccentable()
            Text(formatWatts(entry.stale ? 0 : s.total))
                .font(.system(size: big ? 30 : 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
    }

    private func caption(_ s: ChargerState) -> some View {
        Group {
            if entry.stale {
                Text("нет связи · \(s.date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Anker Prime")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
    }

    private func small(_ s: ChargerState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            caption(s)
            header(s, big: false)
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                ForEach(s.pads) { pad in
                    PadRing(pad: pad, size: 36, showsLabel: false)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 4)
        }
    }

    private func medium(_ s: ChargerState) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                caption(s)
                header(s, big: true)
                Spacer(minLength: 0)
                Text(activeSummary(s))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: 120, alignment: .leading)
            HStack(spacing: 10) {
                ForEach(s.pads) { pad in
                    PadRing(pad: pad, size: 50, showsLabel: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func activeSummary(_ s: ChargerState) -> String {
        let n = entry.stale ? 0 : s.pads.filter(\.isCharging).count
        switch n {
        case 0: return "ничего не заряжается"
        case 1: return "заряжается 1 устройство"
        default: return "заряжается \(n) устройства"
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.slash.fill").font(.title2)
            Text("Нет данных.\nЗапустите AnkerBar")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}
