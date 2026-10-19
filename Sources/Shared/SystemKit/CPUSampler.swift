import Foundation
import Darwin

// Liest die CPU-Auslastung über host_processor_info. Die Tick-Zähler sind
// kumulativ, deshalb wird je Aufruf die Differenz zum vorigen Stand gebildet.
final class CPUSampler {
    struct Reading {
        var total: Double = 0          // 0...1 über alle Kerne
        var perCore: [Double] = []     // 0...1 je Kern
    }

    private var previous: [UInt32]?

    func sample() -> Reading {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else {
            return Reading()
        }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info))), size)
        }

        let cores = Int(cpuCount)
        let states = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: cores * states)
        for i in 0..<(cores * states) {
            ticks[i] = UInt32(bitPattern: info[i])
        }
        defer { previous = ticks }

        guard let prev = previous, prev.count == ticks.count else {
            // Erster Aufruf liefert nur die Grundlinie.
            return Reading(total: 0, perCore: [Double](repeating: 0, count: cores))
        }

        var perCore = [Double](repeating: 0, count: cores)
        var busySum = 0.0
        var totalSum = 0.0
        for core in 0..<cores {
            let base = core * states
            let user = Double(ticks[base + Int(CPU_STATE_USER)] &- prev[base + Int(CPU_STATE_USER)])
            let system = Double(ticks[base + Int(CPU_STATE_SYSTEM)] &- prev[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(ticks[base + Int(CPU_STATE_IDLE)] &- prev[base + Int(CPU_STATE_IDLE)])
            let nice = Double(ticks[base + Int(CPU_STATE_NICE)] &- prev[base + Int(CPU_STATE_NICE)])
            let busy = user + system + nice
            let total = busy + idle
            perCore[core] = total > 0 ? busy / total : 0
            busySum += busy
            totalSum += total
        }
        return Reading(total: totalSum > 0 ? busySum / totalSum : 0, perCore: perCore)
    }
}
