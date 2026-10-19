import SwiftUI

// Einfaches umbruchfähiges Layout (links nach rechts, dann nächste Zeile).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxWidth, widest), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                       anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// Ein Ring-Messer: Spur, farbiger Bogen und ein Wert in der Mitte.
struct RingGauge: View {
    let fraction: Double
    let centerText: String
    let label: String
    let color: Color
    var size: CGFloat = 58
    var lineWidth: CGFloat = 7

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0.0001), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(centerText)
                    .font(.system(size: size * 0.30, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.35), value: fraction)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// Eine Zeile der Balkenliste: farbiges Symbolfeld, Beschriftung, Wert, Balken.
struct BarRow: View {
    let metric: Metric
    let snapshot: SystemSnapshot

    var body: some View {
        let fraction = snapshot.fraction(for: metric) ?? 0
        HStack(spacing: 9) {
            Image(systemName: metric.symbol)
                .font(.system(size: 12))
                .foregroundStyle(metric.accent)
                .frame(width: 24, height: 24)
                .background(metric.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(metric.title).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.display(for: metric))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(metric.accent)
                            .frame(width: max(0, geo.size.width * fraction))
                            .animation(.easeOut(duration: 0.35), value: fraction)
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// Eine Sparkline (Fläche plus Linie) aus 0...1-Werten. Skaliert auf das eigene
// Maximum, damit auch kleine Schwankungen sichtbar bleiben.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for point in pts { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.16))
                    Path { path in
                        path.move(to: pts[0])
                        for point in pts.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let scale = max(values.max() ?? 0.1, 0.1)
        let count = values.count
        return values.enumerated().map { index, value in
            let x = count == 1 ? size.width : size.width * CGFloat(index) / CGFloat(count - 1)
            let normalized = min(value / scale, 1)
            let y = size.height * (1 - CGFloat(normalized) * 0.85) - 1
            return CGPoint(x: x, y: max(1, y))
        }
    }
}

// Ein halbkreisförmiger Bogen (Tacho), Zentrum unten in der Mitte.
struct ArcShape: Shape {
    var endFraction: Double      // 0...1 des oberen Halbkreises

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2, rect.height)
        let start = Angle.degrees(180)
        let end = Angle.degrees(180 + 180 * min(max(endFraction, 0), 1))
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

struct SemiGauge: View {
    let fraction: Double
    let color: Color
    let centerText: String
    let caption: String

    var body: some View {
        ZStack {
            VStack {
                ZStack(alignment: .bottom) {
                    ArcShape(endFraction: 1)
                        .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    ArcShape(endFraction: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .animation(.easeOut(duration: 0.35), value: fraction)
                }
                .frame(height: 56)
            }
            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 10)
        }
        .frame(height: 64)
    }
}
