import SwiftUI

// Das aufklappbare Panel: Kopfzeile, die zusammengestellten Bausteine (oder der
// Konfigurator) und eine Fußzeile.
struct PanelView: View {
    @EnvironmentObject private var sampler: SystemSampler
    @EnvironmentObject private var config: AppConfig
    @State private var showConfig = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)

            if showConfig {
                ConfiguratorView()
            } else {
                modules
            }

            Divider().padding(.vertical, 10)
            footer
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { sampler.setInterval(config.intervalSeconds) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("Leitwarte").font(.system(size: 12, weight: .medium))
            Spacer()
            Text(intervalLabel)
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var intervalLabel: String {
        let value = config.intervalSeconds
        if value < 1 { return Fmt.comma(String(format: "%.1f", value)) + " s" }
        return "\(Int(value)) s"
    }

    @ViewBuilder
    private var modules: some View {
        let enabled = config.enabledModules
        if enabled.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 20)).foregroundStyle(.tertiary)
                Text("Keine Anzeige aktiv")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Unten auf \u{201E}Anpassen\u{201C} tippen.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(enabled.enumerated()), id: \.element.id) { index, module in
                    ModuleView(config: module, snapshot: sampler.snapshot, history: sampler.history)
                        .padding(.vertical, index == 0 ? 0 : 12)
                    if index < enabled.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showConfig.toggle() }
            } label: {
                Label(showConfig ? "Fertig" : "Anpassen",
                      systemImage: showConfig ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(showConfig ? Color.accentColor : .secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Beenden", systemImage: "power").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
