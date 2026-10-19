import Foundation
import SwiftUI
import WidgetKit

// Orchestriert alle Sampler im festen Takt und veröffentlicht die jeweils
// jüngste Momentaufnahme samt Verlauf an die Oberfläche.
@MainActor
final class SystemSampler: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history = MetricHistory()

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let power = PowerSampler()
    private let temperature = TemperatureSampler()
    private let smc = SMCSampler()

    private var timer: Timer?
    private var started = false
    private var tickCount = 0
    private(set) var interval: TimeInterval = 1.0

    init() {
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        power.start()
        temperature.start()
        smc.start()
        tick()          // Grundlinie setzen
        schedule()
    }

    func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        // .common-Modus, damit die Werte auch aktualisiert werden, während das
        // Menü geöffnet ist (dann läuft der Runloop im Tracking-Modus).
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let cpuReading = cpu.sample()
        let memoryReading = memory.sample()
        let gpuReading = gpu.sample()
        let powerReading = power.sample()

        var snap = SystemSnapshot()
        snap.cpu = cpuReading.total
        snap.perCore = cpuReading.perCore
        snap.ramFraction = memoryReading.fraction
        snap.ramUsedBytes = memoryReading.usedBytes
        snap.ramTotalBytes = memoryReading.totalBytes
        snap.gpu = gpuReading
        // Energie zeigt die gesamte Systemleistung (SMC), sonst die Rechenleistung.
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

        snapshot = snap
        history.append(snap)

        // Für das Schreibtisch-Widget in den geteilten Speicher schreiben und das
        // Widget gelegentlich zum Aktualisieren anstoßen (das System drosselt selbst).
        SnapshotStore.write(snap)
        tickCount += 1
        if tickCount % 60 == 0 {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
