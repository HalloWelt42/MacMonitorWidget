import Foundation

// Feste Eckdaten des Chips: Name, Kernzahlen je Leistungsstufe, Speicher und die
// Taktstufen (MHz), mit denen sich die IOReport-Residenzen in Takt und
// Auslastung umrechnen lassen. Wird einmal beim Start gelesen.
struct ChipInfo: Codable, Equatable {
    var name: String = "Apple Silicon"
    var eCores: Int = 0              // untere Stufe (Effizienz, auf M5+ "Performance")
    var pCores: Int = 0              // obere Stufe (Leistung, auf M5+ "Super")
    var eLabel: String = "E"
    var pLabel: String = "P"
    var gpuCores: Int = 0
    var memoryGB: Int = 0
    var eFrequencies: [Double] = []  // MHz, aufsteigend
    var pFrequencies: [Double] = []
    var gpuFrequencies: [Double] = []

    static let empty = ChipInfo()

    // Kopfzeile wie "Apple M4 Max (4E+12P+40GPU 128GB)".
    var headline: String {
        "\(name) (\(eCores)\(eLabel)+\(pCores)\(pLabel)+\(gpuCores)GPU \(memoryGB)GB)"
    }
}
