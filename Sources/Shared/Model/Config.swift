import SwiftUI

// Die verfügbaren Bausteine.
enum ModuleKind: String, CaseIterable, Identifiable, Codable {
    case ringe
    case balken
    case verlauf
    case minimal
    case tacho

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringe: return "Ringe"
        case .balken: return "Balken"
        case .verlauf: return "Verlauf"
        case .minimal: return "Minimal"
        case .tacho: return "Tacho"
        }
    }

    var symbol: String {
        switch self {
        case .ringe: return "circle.dashed"
        case .balken: return "chart.bar.fill"
        case .verlauf: return "waveform.path.ecg"
        case .minimal: return "number"
        case .tacho: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    var blurb: String {
        switch self {
        case .ringe: return "Ringe nebeneinander"
        case .balken: return "Liste mit genauen Werten"
        case .verlauf: return "Sparklines über die Zeit"
        case .minimal: return "Eine Kennzahl groß"
        case .tacho: return "Gesamtlast als Zeiger"
        }
    }
}

// Ein konfigurierter Baustein im Panel.
struct ModuleConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ModuleKind
    var metrics: [Metric]
    var enabled: Bool
}

// Was im Menüleisten-Symbol selbst steht.
enum MenuBarStyle: String, CaseIterable, Identifiable, Codable {
    case cpuPercent
    case cpuLabeled
    case cpuAndRam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuPercent: return "CPU in Prozent"
        case .cpuLabeled: return "CPU beschriftet"
        case .cpuAndRam: return "CPU und RAM"
        }
    }
}

// Persistente Zusammenstellung: welche Bausteine in welcher Reihenfolge, mit
// welchen Metriken, plus Takt und Menüleisten-Stil.
@MainActor
final class AppConfig: ObservableObject {
    @Published var modules: [ModuleConfig] { didSet { save() } }
    @Published var intervalSeconds: Double { didSet { save() } }
    @Published var menuBarStyle: MenuBarStyle { didSet { save() } }

    private static let storageKey = "leitwarte.config.v1"

    init() {
        if let stored = Self.loadStored() {
            modules = stored.modules
            intervalSeconds = stored.intervalSeconds
            menuBarStyle = stored.menuBarStyle
        } else {
            modules = Self.defaultModules
            intervalSeconds = 1
            menuBarStyle = .cpuPercent
        }
    }

    var enabledModules: [ModuleConfig] {
        modules.filter { $0.enabled && !$0.metrics.isEmpty }
    }

    func toggleEnabled(_ id: UUID) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].enabled.toggle()
    }

    func toggleMetric(_ metric: Metric, in id: UUID) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        if let position = modules[index].metrics.firstIndex(of: metric) {
            modules[index].metrics.remove(at: position)
        } else {
            // Reihenfolge der Metriken stabil halten.
            modules[index].metrics = Metric.allCases.filter {
                modules[index].metrics.contains($0) || $0 == metric
            }
        }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < modules.count else { return }
        modules.swapAt(index, target)
    }

    // MARK: - Persistenz

    private struct Stored: Codable {
        var modules: [ModuleConfig]
        var intervalSeconds: Double
        var menuBarStyle: MenuBarStyle
    }

    private func save() {
        let stored = Stored(modules: modules, intervalSeconds: intervalSeconds, menuBarStyle: menuBarStyle)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func loadStored() -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return nil
        }
        return stored
    }

    private static let defaultModules: [ModuleConfig] = [
        ModuleConfig(kind: .ringe, metrics: [.cpu, .ram, .gpu, .energy], enabled: true),
        ModuleConfig(kind: .balken, metrics: [.cpu, .ram, .gpu, .energy, .temperature], enabled: true),
        ModuleConfig(kind: .verlauf, metrics: [.cpu, .energy], enabled: true),
        ModuleConfig(kind: .minimal, metrics: [.cpu, .ram, .gpu], enabled: false),
        ModuleConfig(kind: .tacho, metrics: [.cpu, .ram, .gpu], enabled: false)
    ]
}
