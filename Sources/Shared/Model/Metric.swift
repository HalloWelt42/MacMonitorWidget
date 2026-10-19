import SwiftUI

// Die messbaren Größen. Jede Metrik kennt ihren Titel, ihre Akzentfarbe und ihr
// Symbol - so bleibt die Darstellung über alle Bausteine hinweg einheitlich.
enum Metric: String, CaseIterable, Identifiable, Codable {
    case cpu
    case ram
    case gpu
    case energy
    case temperature
    case fan
    case swap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .gpu: return "GPU"
        case .energy: return "Energie"
        case .temperature: return "Temperatur"
        case .fan: return "Lüfter"
        case .swap: return "Swap"
        }
    }

    var accent: Color {
        switch self {
        case .cpu: return Color(hex: 0x3A8ADF)
        case .ram: return Color(hex: 0x9B8CF0)
        case .gpu: return Color(hex: 0x34C98A)
        case .energy: return Color(hex: 0xF5A623)
        case .temperature: return Color(hex: 0xE0533F)
        case .fan: return Color(hex: 0x22B8C9)
        case .swap: return Color(hex: 0x7E8AA2)
        }
    }

    // SF-Symbols-Name für die Balkenliste.
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .gpu: return "display"
        case .energy: return "bolt.fill"
        case .temperature: return "thermometer.medium"
        case .fan: return "fanblades.fill"
        case .swap: return "arrow.up.arrow.down"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
