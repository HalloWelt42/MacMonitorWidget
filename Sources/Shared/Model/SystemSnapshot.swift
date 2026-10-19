import Foundation

// Eine Momentaufnahme aller Messwerte. Optionale Felder sind "nicht verfügbar"
// (z. B. Energie auf Geräten ohne lesbare Energie-Kanäle).
struct SystemSnapshot: Codable {
    var cpu: Double = 0                 // 0...1 Gesamtauslastung
    var perCore: [Double] = []          // 0...1 je Kern
    var ramFraction: Double = 0         // 0...1
    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 0
    var gpu: Double? = nil              // 0...1
    var powerWatts: Double? = nil       // Paketleistung
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
    var temperature: Double? = nil      // Grad Celsius
    var fanRPM: Double? = nil           // Umdrehungen pro Minute
    var fanMaxRPM: Double? = nil
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var swapFraction: Double = 0        // 0...1

    // Bezugsgröße, um Watt (Systemleistung) für Ringe/Tacho auf 0...1 zu normieren.
    static let powerScale: Double = 60.0
    // Bezugsdrehzahl, falls der SMC keine Maximaldrehzahl meldet.
    static let fanScale: Double = 6500.0

    // Anteil 0...1 für Ringe, Balken und Tacho. Energie wird auf powerScale bezogen.
    func fraction(for metric: Metric) -> Double? {
        switch metric {
        case .cpu: return cpu
        case .ram: return ramFraction
        case .gpu: return gpu
        case .energy: return powerWatts.map { min($0 / Self.powerScale, 1) }
        case .temperature: return temperature.map { min($0 / 100.0, 1) }
        case .fan: return fanRPM.map { min($0 / (fanMaxRPM ?? Self.fanScale), 1) }
        case .swap: return swapFraction
        }
    }

    // Ausführliche Beschriftung für die Balkenliste.
    func display(for metric: Metric) -> String {
        switch metric {
        case .cpu: return Fmt.percent(cpu)
        case .ram: return "\(Fmt.gib(ramUsedBytes)) / \(Fmt.gibWhole(ramTotalBytes))"
        case .gpu: return gpu.map(Fmt.percent) ?? "n/v"
        case .energy: return powerWatts.map(Fmt.watts) ?? "n/v"
        case .temperature: return temperature.map { "\(Int($0.rounded())) \u{00B0}C" } ?? "n/v"
        case .fan: return fanRPM.map { "\(Int($0.rounded())) U/min" } ?? "n/v"
        case .swap: return swapTotalBytes > 0 ? "\(Fmt.gib(swapUsedBytes)) / \(Fmt.gibWhole(swapTotalBytes))" : "0 GB"
        }
    }

    // Mittellange Beschriftung für Verlauf-/Minimal-Zeilen, z. B. "38%" oder "12,4 W".
    func badge(for metric: Metric) -> String {
        switch metric {
        case .cpu: return Fmt.percent(cpu)
        case .ram: return Fmt.percent(ramFraction)
        case .gpu: return gpu.map(Fmt.percent) ?? "n/v"
        case .energy: return powerWatts.map(Fmt.watts) ?? "n/v"
        case .temperature: return temperature.map { "\(Int($0.rounded())) \u{00B0}C" } ?? "n/v"
        case .fan: return fanRPM.map { "\(Int($0.rounded())) U/min" } ?? "n/v"
        case .swap: return Fmt.percent(swapFraction)
        }
    }

    // Wert unter einem Widget-Ring: RAM als ganze GB, Energie als Watt mit einer
    // Nachkommastelle, Temperatur in Grad, der Rest in Prozent.
    func widgetValue(for metric: Metric) -> String {
        switch metric {
        case .cpu: return Fmt.percent(cpu)
        case .ram: return ramTotalBytes > 0 ? Fmt.gibWhole(ramUsedBytes) : "n/v"
        case .gpu: return gpu.map(Fmt.percent) ?? "n/v"
        case .energy: return powerWatts.map(Fmt.watts) ?? "n/v"
        case .temperature: return temperature.map { "\(Int($0.rounded())) \u{00B0}C" } ?? "n/v"
        case .fan: return fanRPM.map { "\(Int($0.rounded())) U/min" } ?? "n/v"
        case .swap: return Fmt.percent(swapFraction)
        }
    }

    // Kurzform für die Mitte eines Rings, z. B. "38" oder "12W".
    func compact(for metric: Metric) -> String {
        switch metric {
        case .cpu: return Fmt.percentValue(cpu)
        case .ram: return Fmt.percentValue(ramFraction)
        case .gpu: return gpu.map(Fmt.percentValue) ?? "-"
        case .energy: return powerWatts.map(Fmt.wattsShort) ?? "-"
        case .temperature: return temperature.map { "\(Int($0.rounded()))\u{00B0}" } ?? "-"
        case .fan: return fanRPM.map { "\(Int($0.rounded()))" } ?? "-"
        case .swap: return Fmt.percentValue(swapFraction)
        }
    }
}
