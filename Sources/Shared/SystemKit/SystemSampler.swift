import Foundation
import SwiftUI
import WidgetKit

// Orchestriert alle Sampler im festen Takt und veröffentlicht die jeweils
// jüngste Momentaufnahme samt Verlauf an die Oberfläche.
@MainActor
final class SystemSampler: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history = MetricHistory()
    private(set) var chipTrace: ChipTrace

    private let probe: SystemProbe

    private var timer: Timer?
    private var started = false
    private var tickCount = 0
    private(set) var interval: TimeInterval = 1.0

    init() {
        let chip = ChipInfoReader.read()
        probe = SystemProbe(chip: chip)
        chipTrace = ChipTrace(chip: chip)
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        probe.start()   // Grundlinien; der erste Messpunkt folgt nach einem Takt
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
        let measurement = probe.measure()
        snapshot = measurement.snapshot
        history.append(measurement.snapshot)
        chipTrace.append(measurement.chipSample)

        // Für das Schreibtisch-Widget in den geteilten Speicher schreiben und das
        // Widget gelegentlich zum Aktualisieren anstoßen (das System drosselt selbst).
        SharedStore.write(measurement.snapshot, as: .snapshot)
        SharedStore.write(chipTrace, as: .chipTrace)
        tickCount += 1
        if tickCount % 60 == 0 {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
