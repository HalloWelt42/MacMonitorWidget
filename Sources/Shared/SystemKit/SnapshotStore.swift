import Foundation

// Geteilter Speicher zwischen App und Widget. Das (unsandboxed) Menüleisten-
// Programm schreibt die jeweils jüngste Momentaufnahme in den App-Gruppen-Ordner,
// das (sandboxed) Widget liest sie dort - so zeigt das Widget auch die Werte, die
// es in der Sandbox nicht selbst messen darf (GPU, Energie, Temperatur).
enum SnapshotStore {
    static let appGroup = "group.tech.leitwarte.app"
    private static let fileName = "snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func write(_ snapshot: SystemSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> SystemSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SystemSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
