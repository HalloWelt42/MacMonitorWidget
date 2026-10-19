import SwiftUI

// Baustein 1: Ringe nebeneinander.
struct RingeView: View {
    let snapshot: SystemSnapshot
    let metrics: [Metric]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(metrics) { metric in
                RingGauge(
                    fraction: snapshot.fraction(for: metric) ?? 0,
                    centerText: snapshot.compact(for: metric),
                    label: metric.title,
                    color: metric.accent
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// Baustein 2: Balkenliste.
struct BalkenView: View {
    let snapshot: SystemSnapshot
    let metrics: [Metric]

    var body: some View {
        VStack(spacing: 11) {
            ForEach(metrics) { metric in
                BarRow(metric: metric, snapshot: snapshot)
            }
        }
    }
}

// Baustein 3: Verlauf als Sparklines.
struct VerlaufView: View {
    let snapshot: SystemSnapshot
    let history: MetricHistory
    let metrics: [Metric]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(metrics) { metric in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.title)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(snapshot.badge(for: metric))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(metric.accent)
                    }
                    .frame(width: 62, alignment: .leading)
                    Sparkline(values: history.values(for: metric), color: metric.accent)
                        .frame(height: 30)
                }
            }
        }
    }
}

// Baustein 4: eine Kennzahl groß, der Rest klein.
struct MinimalView: View {
    let snapshot: SystemSnapshot
    let metrics: [Metric]

    var body: some View {
        let hero = metrics.first ?? .cpu
        let rest = Array(metrics.dropFirst())
        VStack(alignment: .leading, spacing: 8) {
            Text(hero.title)
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(snapshot.compact(for: hero))
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                if hero != .energy {
                    Text("%").font(.system(size: 22)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(hero.accent)
                        .frame(width: max(0, geo.size.width * (snapshot.fraction(for: hero) ?? 0)))
                }
            }
            .frame(height: 5)

            if !rest.isEmpty {
                HStack(spacing: 8) {
                    ForEach(rest) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.title)
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(snapshot.badge(for: metric))
                                .font(.system(size: 14, weight: .medium).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// Baustein 5: Tacho für die mittlere Gesamtlast.
struct TachoView: View {
    let snapshot: SystemSnapshot
    let metrics: [Metric]

    private var overall: Double {
        let values = metrics.compactMap { snapshot.fraction(for: $0) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(spacing: 8) {
            SemiGauge(
                fraction: overall,
                color: Metric.cpu.accent,
                centerText: Fmt.percent(overall),
                caption: "ausgelastet"
            )
            HStack(spacing: 12) {
                ForEach(metrics) { metric in
                    HStack(spacing: 4) {
                        Text(snapshot.compact(for: metric))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(metric.accent)
                        Text(metric.title)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// Setzt einen konfigurierten Baustein in die passende Ansicht um.
struct ModuleView: View {
    let config: ModuleConfig
    let snapshot: SystemSnapshot
    let history: MetricHistory

    var body: some View {
        switch config.kind {
        case .ringe:
            RingeView(snapshot: snapshot, metrics: config.metrics)
        case .balken:
            BalkenView(snapshot: snapshot, metrics: config.metrics)
        case .verlauf:
            VerlaufView(snapshot: snapshot, history: history, metrics: config.metrics)
        case .minimal:
            MinimalView(snapshot: snapshot, metrics: config.metrics)
        case .tacho:
            TachoView(snapshot: snapshot, metrics: config.metrics)
        }
    }
}
