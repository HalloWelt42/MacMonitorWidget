import Foundation
import IOKit

// Liest die GPU-Auslastung aus dem IORegistry. Die IOAccelerator-Dienste führen
// unter "PerformanceStatistics" eine Auslastungskennzahl. Der genaue Schlüssel
// unterscheidet sich je nach GPU, deshalb werden mehrere Kandidaten geprüft.
final class GPUSampler {
    private let candidateKeys = [
        "Device Utilization %",
        "GPU Activity(%)",
        "Renderer Utilization %",
        "GPU Core Utilization %"
    ]

    // Liefert (Auslastung 0...1, verwendeter Schlüssel) oder nil. Je Beschleuniger
    // wird die höchstpriorisierte vorhandene Kennzahl genommen; bei mehreren GPUs
    // gewinnt die höchste Auslastung.
    func readUtilization() -> (value: Double, key: String)? {
        var best: (Double, String)?
        forEachAccelerator { perf in
            for key in candidateKeys {
                guard let number = perf[key] as? NSNumber else { continue }
                let fraction = min(number.doubleValue / 100.0, 1)
                if best == nil || fraction > best!.0 {
                    best = (fraction, key)
                }
                break   // nur die erste vorhandene Kennzahl je Beschleuniger
            }
        }
        return best.map { (value: $0.0, key: $0.1) }
    }

    func sample() -> Double? {
        readUtilization()?.value
    }

    // Alle PerformanceStatistics-Wörterbücher für den Dump-Modus.
    func diagnostics() -> [(service: String, stats: [String: Any])] {
        var out: [(String, [String: Any])] = []
        var index = 0
        forEachAccelerator(includeName: true) { name, perf in
            out.append((name ?? "accelerator\(index)", perf))
            index += 1
        }
        return out
    }

    private func forEachAccelerator(_ body: ([String: Any]) -> Void) {
        forEachAccelerator(includeName: false) { _, perf in body(perf) }
    }

    private func forEachAccelerator(includeName: Bool, _ body: (String?, [String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                let name = includeName ? (dict["IOClass"] as? String) : nil
                body(name, perf)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
