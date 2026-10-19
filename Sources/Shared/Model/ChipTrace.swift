import Foundation

// Verlauf der Chip-Übersicht: die letzten Messpunkte (älteste zuerst) samt
// Chip-Eckdaten. Alle Anzeigewerte (geglätteter Wert, Mittel, Höchstwert,
// Temperatur) werden aus den Messpunkten abgeleitet - eine einzige Wahrheit,
// die das Programm schreibt und das Widget liest.
struct ChipTrace: Codable {
    static let capacity = 128

    var chip: ChipInfo = .empty
    private(set) var samples: [ChipSample] = []

    init(chip: ChipInfo = .empty) {
        self.chip = chip
    }

    mutating func append(_ sample: ChipSample) {
        samples.append(sample)
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    var latest: ChipSample { samples.last ?? ChipSample() }

    // MARK: - Abgeleitete Reihen

    func series(_ value: (ChipSample) -> Double) -> [Double] {
        samples.map(value)
    }

    // Leistung wie in der Vorlage: angezeigt wird das Mittel aus letztem und
    // vorletztem Wert (beruhigt Sprünge), dazu Mittel und Höchstwert des Verlaufs.
    func power(_ value: (ChipSample) -> Double) -> PowerFigures {
        let items = series(value)
        guard let current = items.last else { return PowerFigures() }
        let previous = items.count > 1 ? items[items.count - 2] : 0
        return PowerFigures(
            current: previous == 0 ? current : (previous + current) / 2,
            average: items.reduce(0, +) / Double(items.count),
            maximum: items.max() ?? 0,
            items: items
        )
    }

    // Temperatur wie in der Vorlage: fehlt ein Wert (0), springt die exponentielle
    // Glättung der letzten acht Werte ein; ohne jeden Sensor bleibt es bei 0.
    func temperature(_ value: (ChipSample) -> Double) -> Double {
        var recent: [Double] = []       // jüngster Wert zuerst, höchstens 8
        for sample in samples {
            let reading = value(sample)
            let filled = reading == 0 ? Self.trend(recent, alpha: 0.8) : reading
            guard filled != 0 else { continue }
            recent.insert(filled, at: 0)
            if recent.count > 8 { recent.removeLast() }
        }
        return recent.first ?? 0
    }

    private static func trend(_ recent: [Double], alpha: Double) -> Double {
        guard recent.count >= 2 else { return 0 }
        let chronological = Array(recent.reversed())
        return chronological.dropFirst().reduce(chronological[0]) { alpha * $1 + (1 - alpha) * $0 }
    }
}

struct PowerFigures {
    var current: Double = 0
    var average: Double = 0
    var maximum: Double = 0
    var items: [Double] = []
}
