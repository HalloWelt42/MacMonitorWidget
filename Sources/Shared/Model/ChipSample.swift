import Foundation

// Takt und Auslastung eines Kerns, eines Clusters oder der GPU in einem Messfenster.
struct CoreActivity: Codable, Equatable {
    var mhz: Double = 0
    var usage: Double = 0    // 0...1, auf den Höchsttakt bezogen (wie die Anzeige)
    var active: Double = 0   // 0...1, reine Aktivzeit ohne Taktbezug

    // Cluster-Mittel: Takt als ganzzahliges Mittel der Kerne, Auslastung als Mittel.
    static func average(_ cores: [CoreActivity]) -> CoreActivity {
        guard !cores.isEmpty else { return CoreActivity() }
        let count = Double(cores.count)
        return CoreActivity(
            mhz: (cores.map(\.mhz).reduce(0, +) / count).rounded(.down),
            usage: cores.map(\.usage).reduce(0, +) / count,
            active: cores.map(\.active).reduce(0, +) / count
        )
    }
}

// Ein Messpunkt für die Chip-Übersicht. Temperaturen sind 0, wenn kein Sensor
// lesbar war; die Glättung darüber übernimmt der Verlauf.
struct ChipSample: Codable {
    var date = Date()
    var eCluster = CoreActivity()
    var pCluster = CoreActivity()
    var gpu = CoreActivity()
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
    var systemWatts: Double? = nil       // nil ohne lesbaren Systemsensor
    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var cpuTemperature: Double = 0
    var gpuTemperature: Double = 0
    var fanRPM: [Int] = []

    // Rechenleistung: CPU + GPU + Neural Engine.
    var computeWatts: Double { cpuWatts + gpuWatts + aneWatts }
}
