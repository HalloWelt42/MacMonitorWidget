import Foundation

// Besitzt alle Sampler und bildet je Aufruf eine vollständige Messung: die
// Momentaufnahme für Bausteine und Menüleiste sowie den Messpunkt für die
// Chip-Übersicht. Einzige Stelle, an der Rohwerte zu Modellwerten werden.
final class SystemProbe {
    struct Measurement {
        var snapshot: SystemSnapshot
        var chipSample: ChipSample
    }

    let chip: ChipInfo
    let cpu = CPUSampler()
    let memory = MemorySampler()
    let gpu = GPUSampler()
    let ioreport: IOReportSampler
    let temperature = TemperatureSampler()
    let smc = SMCSampler()

    init(chip: ChipInfo) {
        self.chip = chip
        ioreport = IOReportSampler(chip: chip)
    }

    // Öffnet die Quellen und setzt die Grundlinien für die ersten Differenzen.
    func start() {
        _ = cpu.sample()
        ioreport.start()
        temperature.start()
        smc.start()
    }

    func measure() -> Measurement {
        let cpuReading = cpu.sample()
        let memoryReading = memory.sample()
        let io = ioreport.sample()
        let systemPower = smc.systemPower()
        let temperatures = smc.hasTemperatureKeys ? smc.temperatures() : temperature.clusterTemperatures()
        let fans = smc.fanSpeeds()

        var snap = SystemSnapshot()
        snap.cpu = cpuReading.total
        snap.perCore = cpuReading.perCore
        snap.ramFraction = memoryReading.fraction
        snap.ramUsedBytes = memoryReading.usedBytes
        snap.ramTotalBytes = memoryReading.totalBytes
        snap.gpu = gpu.sample()
        // Energie zeigt die gesamte Systemleistung (SMC), sonst die Rechenleistung.
        snap.powerWatts = systemPower ?? io?.computeWatts
        snap.cpuWatts = io?.cpuWatts
        snap.gpuWatts = io?.gpuWatts
        snap.temperature = temperature.sample()
        snap.swapUsedBytes = memoryReading.swapUsedBytes
        snap.swapTotalBytes = memoryReading.swapTotalBytes
        snap.swapFraction = memoryReading.swapFraction
        if !fans.isEmpty {
            snap.fanRPM = Double(fans.reduce(0, +)) / Double(fans.count)
            snap.fanMaxRPM = smc.fan()?.maxRPM
        }

        var sample = ChipSample()
        if let io {
            sample.eCluster = CoreActivity.average(io.eCores)
            sample.pCluster = CoreActivity.average(io.pCores)
            sample.gpu = io.gpu
            sample.cpuWatts = io.cpuWatts
            sample.gpuWatts = io.gpuWatts
            sample.aneWatts = io.aneWatts
        }
        // Die Systemleistung ist nie kleiner als die Rechenleistung, die sie enthält.
        sample.systemWatts = systemPower.map { max($0, sample.computeWatts) }
        sample.ramUsedBytes = memoryReading.usedBytes
        sample.ramTotalBytes = memoryReading.totalBytes
        sample.swapUsedBytes = memoryReading.swapUsedBytes
        sample.swapTotalBytes = memoryReading.swapTotalBytes
        sample.cpuTemperature = temperatures.cpu
        sample.gpuTemperature = temperatures.gpu
        sample.fanRPM = fans

        return Measurement(snapshot: snap, chipSample: sample)
    }
}
