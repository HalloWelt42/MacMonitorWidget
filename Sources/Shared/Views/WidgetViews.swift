import SwiftUI

// Die Inhalte des Schreibtisch-Widgets je Größe. Bewusst ohne WidgetKit-Bezug,
// damit sie auch in der App-Vorschau (Snapshot-Modus) gerendert werden können.
// Kein Verlauf-Baustein, da ein Widget je Aktualisierung nur einen Wert kennt.
//
// Stil angelehnt an die System-Batterien-Widgets: einheitliche Ringfarbe, Symbol
// in der Mitte, Wert darunter, heller Inhalt für den transparenten Hintergrund.

enum WidgetTheme {
    static let ring = Color(hex: 0x5BCB6E)        // einheitliche Ringfarbe
    static let track = Color.white.opacity(0.22)
    static let icon = Color.white
    static let value = Color.white.opacity(0.9)
}

// Standard-Metriken des Widgets: Temperatur statt CPU.
private let widgetMetrics: [Metric] = [.temperature, .ram, .gpu, .energy]
private let widgetExtraMetrics: [Metric] = [.cpu, .fan, .swap]

struct WidgetRing: View {
    let metric: Metric
    let snapshot: SystemSnapshot
    var size: CGFloat = 60
    var lineWidth: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(WidgetTheme.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(snapshot.fraction(for: metric) ?? 0, 0.001), 1))
                    .stroke(WidgetTheme.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: metric.symbol)
                    .font(.system(size: size * 0.30, weight: .medium))
                    .foregroundStyle(WidgetTheme.icon)
            }
            .frame(width: size, height: size)
            Text(snapshot.widgetValue(for: metric))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WidgetTheme.value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct WidgetSmall: View {
    let snapshot: SystemSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(widgetMetrics) { metric in
                WidgetRing(metric: metric, snapshot: snapshot, size: 52)
            }
        }
    }
}

struct WidgetMedium: View {
    let snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 4) {
            ForEach(widgetMetrics) { metric in
                WidgetRing(metric: metric, snapshot: snapshot, size: 58)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct WidgetLarge: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(widgetMetrics) { metric in
                    WidgetRing(metric: metric, snapshot: snapshot, size: 62)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 4) {
                ForEach(widgetExtraMetrics) { metric in
                    WidgetRing(metric: metric, snapshot: snapshot, size: 62)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
