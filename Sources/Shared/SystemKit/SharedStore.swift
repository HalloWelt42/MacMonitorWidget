import Foundation

// Geteilter Speicher zwischen App und Widget. Das (unsandboxed) Menüleisten-
// Programm schreibt die jüngsten Werte in den App-Gruppen-Ordner, das (sandboxed)
// Widget liest sie dort - so zeigt das Widget auch die Werte, die es in der
// Sandbox nicht selbst messen darf (GPU, Takt, Energie, Temperatur).
enum SharedStore {
    static let appGroup = "group.tech.leitwarte.app"

    // Je Inhalt eine Datei: Momentaufnahme für die Bausteine, Verlauf für die Chip-Übersicht.
    enum Entry: String {
        case snapshot = "snapshot.json"
        case chipTrace = "chip-trace.json"
    }

    static func write<Value: Encodable>(_ value: Value, as entry: Entry) {
        guard let url = fileURL(entry), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read<Value: Decodable>(_ type: Value.Type, from entry: Entry) -> Value? {
        guard let url = fileURL(entry), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func fileURL(_ entry: Entry) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(entry.rawValue)
    }
}
