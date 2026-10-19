import Foundation

// Zahlenausgabe mit deutschem Dezimalkomma. Bewusst ohne NumberFormatter, damit
// die Werte im Sekundentakt günstig formatiert werden.
enum Fmt {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func percentValue(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }

    static func watts(_ value: Double) -> String {
        comma(String(format: "%.1f", value)) + " W"
    }

    static func wattsShort(_ value: Double) -> String {
        "\(Int(value.rounded()))W"
    }

    // Bytes als Gibibyte mit einer Nachkommastelle, z. B. "10,2".
    static func gib(_ bytes: UInt64) -> String {
        comma(String(format: "%.1f", Double(bytes) / 1_073_741_824.0))
    }

    // Gerundetes Gibibyte mit Einheit, z. B. "16 GB".
    static func gibWhole(_ bytes: UInt64) -> String {
        "\(Int((Double(bytes) / 1_073_741_824.0).rounded())) GB"
    }

    static func comma(_ string: String) -> String {
        string.replacingOccurrences(of: ".", with: ",")
    }
}
