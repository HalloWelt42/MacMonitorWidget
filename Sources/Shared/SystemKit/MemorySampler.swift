import Foundation
import Darwin

// Liest den belegten Arbeitsspeicher über host_statistics64. "Belegt" folgt der
// Logik der Aktivitätsanzeige: App-Speicher (interne, nicht verwerfbare Seiten)
// plus fest verdrahteter plus komprimierter Speicher. Datei-Cache (aktiv/inaktiv,
// spekulativ) zählt bewusst NICHT mit, da er bei Bedarf zurückgeholt wird.
final class MemorySampler {
    struct Reading {
        var usedBytes: UInt64 = 0
        var totalBytes: UInt64 = 0
        var fraction: Double = 0
        var swapUsedBytes: UInt64 = 0
        var swapTotalBytes: UInt64 = 0
        var swapFraction: Double = 0
    }

    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    private let totalBytes = ProcessInfo.processInfo.physicalMemory

    func sample() -> Reading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return Reading(usedBytes: 0, totalBytes: totalBytes, fraction: 0)
        }

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let appMemory = internalPages > purgeable ? internalPages - purgeable : 0
        let used = (appMemory + wired + compressed) * pageSize
        let fraction = totalBytes > 0 ? min(Double(used) / Double(totalBytes), 1) : 0

        let swap = swapUsage()
        let swapFraction = swap.total > 0 ? min(Double(swap.used) / Double(swap.total), 1) : 0
        return Reading(
            usedBytes: used,
            totalBytes: totalBytes,
            fraction: fraction,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            swapFraction: swapFraction
        )
    }

    // Swap-Nutzung über sysctl (vm.swapusage).
    private func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (usage.xsu_used, usage.xsu_total)
    }
}
