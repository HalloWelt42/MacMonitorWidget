import Foundation
import IOKit

// Liest die Chip-Eckdaten ohne Hilfsprozesse: Name und Kernzahlen über sysctl,
// GPU-Kerne und Taktstufen aus dem IORegistry (AGXAccelerator, pmgr).
enum ChipInfoReader {
    static func read() -> ChipInfo {
        var info = ChipInfo()
        info.name = sysctlString("machdep.cpu.brand_string") ?? info.name
        info.memoryGB = Int(sysctlInt("hw.memsize") / 1_073_741_824)

        // perflevel0 ist die obere Stufe, perflevel1 die untere. Die Kennbuchstaben
        // folgen den Stufennamen (Performance/Efficiency, auf M5+ Super/Performance).
        info.pCores = Int(sysctlInt("hw.perflevel0.physicalcpu"))
        info.eCores = Int(sysctlInt("hw.perflevel1.physicalcpu"))
        info.pLabel = initial(sysctlString("hw.perflevel0.name")) ?? "P"
        info.eLabel = initial(sysctlString("hw.perflevel1.name")) ?? "E"

        info.gpuCores = gpuCoreCount()
        readFrequencies(into: &info)
        return info
    }

    // MARK: - Taktstufen

    private static func readFrequencies(into info: inout ChipInfo) {
        guard let pmgr = registryProperties(serviceClass: "AppleARMIODevice", name: "pmgr") else { return }
        // M1 bis M3 (und A-Chips) legen die CPU-Stufen in Hz ab, ab M4 in kHz.
        let legacy = ["M1", "M2", "M3", "A1"].contains { info.name.contains($0) }
        let cpuScale: Double = legacy ? 1_000_000 : 1_000

        let clusterKeys = accClusterKeys(pmgr)
        let eKey = pmgr["voltage-states1-sram"] != nil ? "voltage-states1-sram" : clusterKeys?.e
        let pKey = pmgr["voltage-states5-sram"] != nil ? "voltage-states5-sram" : clusterKeys?.p
        if let eKey { info.eFrequencies = frequencies(pmgr[eKey], scale: cpuScale) }
        if let pKey { info.pFrequencies = frequencies(pmgr[pKey], scale: cpuScale) }
        info.gpuFrequencies = frequencies(pmgr["voltage-states9"], scale: 1_000_000)
    }

    // Paare aus (Takt, Spannung) zu je 4 Byte little-endian; nur der Takt zählt.
    private static func frequencies(_ value: Any?, scale: Double) -> [Double] {
        guard let data = value as? Data else { return [] }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - 7, by: 8).map { offset in
            let raw = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return (Double(raw) / scale).rounded(.down)
        }
    }

    // Ersatzweg für Chips ohne die festen Schlüssel (M5+): "acc-clusters" listet je
    // Cluster den Index der voltage-states und die Stufe. Die höchste Stufe ist die
    // obere, die zweithöchste die untere.
    private static func accClusterKeys(_ pmgr: [String: Any]) -> (e: String, p: String)? {
        guard let data = pmgr["acc-clusters"] as? Data, data.count >= 16 else { return nil }
        let bytes = [UInt8](data)
        let clusters = stride(from: 0, to: bytes.count - 7, by: 8)
            .map { (tier: bytes[$0 + 1], key: "voltage-states\(bytes[$0])-sram") }
            .sorted { $0.tier < $1.tier }
        guard clusters.count >= 2 else { return nil }
        return (clusters[clusters.count - 2].key, clusters[clusters.count - 1].key)
    }

    // MARK: - IORegistry

    private static func gpuCoreCount() -> Int {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func registryProperties(serviceClass: String, name: String) -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var buffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS, String(cString: buffer) == name else { continue }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
                return nil
            }
            return properties?.takeRetainedValue() as? [String: Any]
        }
        return nil
    }

    // MARK: - sysctl

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        // Manche Schlüssel sind 32 Bit breit; dann steht der Wert in den unteren Bytes.
        return size == 4 ? value & 0xFFFF_FFFF : value
    }

    private static func initial(_ name: String?) -> String? {
        guard let first = name?.first else { return nil }
        return String(first).uppercased()
    }
}
