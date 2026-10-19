import SwiftUI

// Chip-Übersicht im Terminal-Stil: oben E-/P-CPU, Speicher und GPU mit Takt und
// Auslastung, unten die Leistung von CPU, GPU und Neural Engine. Alle Werte
// stammen aus dem ChipTrace; die Ansicht rechnet nur Anzeigeformen.
struct ChipBoard: View {
    let trace: ChipTrace
    var version: String = ""
    // Ab diesem Alter gilt der letzte Messpunkt als veraltet (Messprogramm beendet).
    var staleAfter: TimeInterval = 120

    private var latest: ChipSample { trace.latest }
    private var chip: ChipInfo { trace.chip }

    var body: some View {
        // Höhen wie in der Vorlage: zwei Drittel Auslastung, ein Drittel Leistung.
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let usable = geometry.size.height - spacing
            VStack(spacing: spacing) {
                usageBlock.frame(height: usable * 2 / 3)
                powerBlock.frame(height: usable / 3)
            }
        }
    }

    private var usageBlock: some View {
        TerminalBox(left: chip.headline, right: version.isEmpty ? "MacMonitorWidget" : "MacMonitorWidget v\(version)") {
            Grid(horizontalSpacing: 6, verticalSpacing: 4) {
                GridRow {
                    frequencyBox("\(chip.eLabel)-CPU", series: \.eCluster)
                    frequencyBox("\(chip.pLabel)-CPU", series: \.pCluster)
                }
                GridRow {
                    memoryBox
                    frequencyBox("GPU", series: \.gpu)
                }
            }
        }
    }

    private var powerBlock: some View {
        TerminalBox(left: powerTitle, right: powerRight, bottomRight: statusText) {
            HStack(spacing: 6) {
                powerBox("CPU", value: \.cpuWatts, temperature: trace.temperature(\.cpuTemperature))
                powerBox("GPU", value: \.gpuWatts, temperature: trace.temperature(\.gpuTemperature))
                powerBox("ANE", value: \.aneWatts, temperature: 0)
            }
        }
    }

    // MARK: - Obere Reihe

    private func frequencyBox(_ label: String, series key: KeyPath<ChipSample, CoreActivity>) -> some View {
        let current = latest[keyPath: key]
        let title = "\(label) \(pad(Int((current.usage * 100).rounded()), 3))% @ \(pad(Int(current.mhz), 4)) MHz"
        return TerminalBox(left: title) {
            BarSparkline(values: trace.series { $0[keyPath: key].usage * 100 }, maximum: 100)
        }
    }

    private var memoryBox: some View {
        let ram = "RAM \(Self.gib(latest.ramUsedBytes, digits: 2)) / \(Self.gib(latest.ramTotalBytes, digits: 1)) GB"
        let swap = "SWAP \(Self.gib(latest.swapUsedBytes, digits: 2)) / \(Self.gib(latest.swapTotalBytes, digits: 1)) GB"
        return TerminalBox(left: ram, right: swap) {
            BarSparkline(values: trace.series { Double($0.ramUsedBytes) },
                         maximum: Double(max(latest.ramTotalBytes, 1)))
        }
    }

    // MARK: - Leistung

    private var powerTitle: String {
        let all = trace.power(\.computeWatts)
        return "Leistung \(Self.watts(all.current)) W (Ø \(Self.watts(all.average)) · max \(Self.watts(all.maximum)))"
    }

    private var powerRight: String {
        var parts: [String] = []
        if !latest.fanRPM.isEmpty {
            let speeds = latest.fanRPM.map(String.init).joined(separator: "/")
            parts.append("Lüfter \(speeds) U/min")
        }
        if latest.systemWatts != nil {
            let system = trace.power { $0.systemWatts ?? 0 }
            parts.append("Gesamt \(Self.watts(system.current)) W (Ø \(Self.watts(system.average)) · max \(Self.watts(system.maximum)))")
        }
        return parts.joined(separator: " | ")
    }

    private func powerBox(_ label: String, value: KeyPath<ChipSample, Double>, temperature: Double) -> some View {
        let figures = trace.power { $0[keyPath: value] }
        let right = temperature > 0 ? String(format: "%.1f\u{00B0}C", temperature).replacingOccurrences(of: ".", with: ",") : ""
        return TerminalBox(left: "\(label) \(Self.watts(figures.current)) W", right: right) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ø \(Self.watts(figures.average)) · max \(Self.watts(figures.maximum))")
                    .font(TerminalTheme.font(TerminalTheme.detailSize))
                    .foregroundStyle(TerminalTheme.foreground.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                BarSparkline(values: figures.items)
            }
        }
    }

    // MARK: - Status

    // Alter der Werte; die Zeitangabe zählt im Widget von selbst weiter.
    private var statusText: Text? {
        guard let date = trace.samples.last?.date else {
            return Text("MacMonitorWidget starten, um Messwerte zu erhalten")
        }
        if Date().timeIntervalSince(date) > staleAfter {
            return Text("Messprogramm beendet, Stand vor ") + Text(date, style: .relative)
        }
        return Text("aktualisiert vor ") + Text(date, style: .relative)
    }

    // MARK: - Zahlen

    private func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: " ", count: max(width - text.count, 0)) + text
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func gib(_ bytes: UInt64, digits: Int) -> String {
        String(format: "%.\(digits)f", Double(bytes) / 1_073_741_824).replacingOccurrences(of: ".", with: ",")
    }
}
