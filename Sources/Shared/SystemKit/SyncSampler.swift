import Foundation

// Misst einmalig eine Momentaufnahme über ein kurzes Fenster. Für Kontexte ohne
// Dauertimer (z. B. die Widget-Zeitleiste), die je Aufruf einen Wert brauchen.
enum SyncSampler {
    static func snapshot(window: useconds_t = 250_000) -> SystemSnapshot {
        let probe = SystemProbe(chip: .empty)
        probe.start()
        usleep(window)
        return probe.measure().snapshot
    }
}
