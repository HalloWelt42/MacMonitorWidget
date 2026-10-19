import SwiftUI

// Der Konfigurator: Bausteine an-/abschalten, Metriken je Baustein wählen,
// Reihenfolge ändern, Takt und Menüleisten-Stil festlegen.
struct ConfiguratorView: View {
    @EnvironmentObject private var config: AppConfig

    private let selectableMetrics: [Metric] = [.cpu, .ram, .gpu, .energy, .temperature, .fan, .swap]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(config.modules.enumerated()), id: \.element.id) { index, module in
                moduleRow(module, index: index)
                if index < config.modules.count - 1 {
                    Divider().opacity(0.5)
                }
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text("Aktualisierung").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $config.intervalSeconds, in: 0.5...10, step: 0.5)
                Text(intervalLabel)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }

            HStack {
                Text("Menüleiste").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $config.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    private var intervalLabel: String {
        let value = config.intervalSeconds
        if value < 1 { return Fmt.comma(String(format: "%.1f", value)) + " s" }
        return "\(Int(value)) s"
    }

    private func moduleRow(_ module: ModuleConfig, index: Int) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                config.toggleEnabled(module.id)
            } label: {
                Image(systemName: module.enabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(module.enabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(module.kind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(module.enabled ? .primary : .secondary)
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(selectableMetrics) { metric in
                        metricChip(metric, in: module)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                moveButton(module, offset: -1, symbol: "chevron.up", enabled: index > 0)
                moveButton(module, offset: 1, symbol: "chevron.down", enabled: index < config.modules.count - 1)
            }
        }
        .padding(.vertical, 2)
    }

    private func metricChip(_ metric: Metric, in module: ModuleConfig) -> some View {
        let selected = module.metrics.contains(metric)
        return Button {
            config.toggleMetric(metric, in: module.id)
        } label: {
            Text(metric.title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    selected ? metric.accent.opacity(0.22) : Color.primary.opacity(0.06),
                    in: Capsule()
                )
                .foregroundStyle(selected ? metric.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func moveButton(_ module: ModuleConfig, offset: Int, symbol: String, enabled: Bool) -> some View {
        Button {
            config.move(module.id, by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? .secondary : .quaternary)
                .frame(width: 18, height: 14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
