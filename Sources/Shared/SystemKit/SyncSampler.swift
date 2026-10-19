import Foundation

// Misst einmalig eine Momentaufnahme über ein kurzes Fenster. Für Kontexte ohne
// Dauertimer (z. B. die Widget-Zeitleiste), die je Aufruf einen Wert brauchen.
enum SyncSampler {
    static func snapshot(window: useconds_t = 250_000) -> SystemSnapshot {
        let cpu = CPUSampler()
        let memory = MemorySampler()
        let gpu = GPUSampler()
        let power = PowerSampler()
        let temperature = TemperatureSampler()
        let smc = SMCSampler()

        _ = cpu.sample()        // CPU- und Energie-Grundlinie
        power.start()
        temperature.start()
        smc.start()
        usleep(window)

        let cpuReading = cpu.sample()
        let memoryReading = memory.sample()
        let powerReading = power.sample()

        var snap = SystemSnapshot()
        snap.cpu = cpuReading.total
        snap.perCore = cpuReading.perCore
        snap.ramFraction = memoryReading.fraction
        snap.ramUsedBytes = memoryReading.usedBytes
        snap.ramTotalBytes = memoryReading.totalBytes
        snap.gpu = gpu.sample()
        snap.powerWatts = smc.systemPower() ?? powerReading.package
        snap.cpuWatts = powerReading.cpu
        snap.gpuWatts = powerReading.gpu
        snap.temperature = temperature.sample()
        snap.swapUsedBytes = memoryReading.swapUsedBytes
        snap.swapTotalBytes = memoryReading.swapTotalBytes
        snap.swapFraction = memoryReading.swapFraction
        if let fan = smc.fan() {
            snap.fanRPM = fan.rpm
            snap.fanMaxRPM = fan.maxRPM
        }
        return snap
    }
}
